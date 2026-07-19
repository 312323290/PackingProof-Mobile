package app.packingproof.mobile

import android.content.Context
import fi.iki.elonen.NanoHTTPD
import fi.iki.elonen.NanoHTTPD.Response.Status
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.Collections
import java.util.concurrent.CopyOnWriteArraySet

internal object OrderInfoReceiverRuntime {
    const val PORT = 5280

    private val listeners = CopyOnWriteArraySet<(List<OrderInfoRecord>) -> Unit>()
    private var server: OrderInfoHttpServer? = null
    private var store: OrderInfoStore? = null
    private var lastError: String? = null

    @Synchronized
    fun start(context: Context): Map<String, Any?> {
        if (server?.wasStarted() == true) return status()
        return try {
            val database = store ?: OrderInfoStore(context.applicationContext).also { store = it }
            server = OrderInfoHttpServer(database) { items ->
                for (listener in listeners) listener(items)
            }.also { it.start(NanoHTTPD.SOCKET_READ_TIMEOUT, false) }
            lastError = null
            status()
        } catch (error: Exception) {
            server = null
            lastError = if (error.message.isNullOrBlank()) "订单接收服务启动失败" else error.message
            status()
        }
    }

    @Synchronized
    fun stop() {
        server?.stop()
        server = null
    }

    @Synchronized
    fun status(): Map<String, Any?> {
        val address = localPrivateIpv4()
        val running = server?.wasStarted() == true
        return mapOf(
            "running" to running,
            "port" to PORT,
            "ipAddress" to (address ?: ""),
            "url" to if (running && address != null) "http://$address:$PORT" else "",
            "errorMessage" to (lastError ?: if (address == null) "请连接局域网 Wi-Fi" else ""),
        )
    }

    @Synchronized
    fun lookup(trackingNumber: String): Map<String, Any>? =
        store?.lookup(trackingNumber)?.toMap()

    fun addListener(listener: (List<OrderInfoRecord>) -> Unit) {
        listeners += listener
    }

    fun removeListener(listener: (List<OrderInfoRecord>) -> Unit) {
        listeners -= listener
    }

    private fun localPrivateIpv4(): String? {
        return try {
            Collections.list(NetworkInterface.getNetworkInterfaces())
                .asSequence()
                .filter {
                    it.isUp && !it.isLoopback &&
                        (it.name.startsWith("wlan", ignoreCase = true) ||
                            it.name.startsWith("eth", ignoreCase = true))
                }
                .flatMap { Collections.list(it.inetAddresses).asSequence() }
                .filterIsInstance<Inet4Address>()
                .map { it.hostAddress ?: "" }
                .firstOrNull(::isPrivateAddress)
        } catch (_: Exception) {
            null
        }
    }

    internal fun isPrivateAddress(value: String): Boolean {
        val clean = value.substringBefore('%')
        val parts = clean.split('.').mapNotNull { it.toIntOrNull() }
        if (parts.size != 4 || parts.any { it !in 0..255 }) return false
        return parts[0] == 10 ||
            (parts[0] == 172 && parts[1] in 16..31) ||
            (parts[0] == 192 && parts[1] == 168) ||
            (parts[0] == 169 && parts[1] == 254) ||
            parts[0] == 127
    }
}

private class OrderInfoHttpServer(
    private val store: OrderInfoStore,
    private val onReceived: (List<OrderInfoRecord>) -> Unit,
) : NanoHTTPD(OrderInfoReceiverRuntime.PORT) {
    override fun serve(session: IHTTPSession): Response {
        val response = try {
            val remoteAddress = session.remoteIpAddress ?: ""
            if (!OrderInfoReceiverRuntime.isPrivateAddress(remoteAddress)) {
                json(Status.FORBIDDEN, JSONObject().put("error", "只允许局域网设备访问"))
            } else {
                route(session)
            }
        } catch (error: IllegalArgumentException) {
            json(Status.BAD_REQUEST, JSONObject().put("error", error.message ?: "请求内容无效"))
        } catch (error: JSONException) {
            json(Status.BAD_REQUEST, JSONObject().put("error", "订单 JSON 格式无效"))
        } catch (error: NanoHTTPD.ResponseException) {
            json(Status.BAD_REQUEST, JSONObject().put("error", error.message ?: "请求内容无效"))
        } catch (error: Exception) {
            json(Status.INTERNAL_ERROR, JSONObject().put("error", error.message ?: "订单接收失败"))
        }
        response.addHeader("Access-Control-Allow-Origin", "*")
        response.addHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        response.addHeader("Access-Control-Allow-Headers", "Content-Type")
        return response
    }

    private fun route(session: IHTTPSession): Response {
        if (session.method == Method.OPTIONS) return json(Status.OK, JSONObject().put("ok", true))
        val path = session.uri.trimEnd('/')
        if (session.method == Method.GET && path == "/api/storage") {
            return json(
                Status.OK,
                JSONObject()
                    .put("ok", true)
                    .put("service", "packingproof-mobile")
                    .put("port", OrderInfoReceiverRuntime.PORT),
            )
        }
        if (path != "/api/orderinfo") return json(Status.NOT_FOUND, JSONObject().put("error", "接口不存在"))
        return when (session.method) {
            Method.GET -> query(session)
            Method.POST -> push(session)
            else -> json(Status.METHOD_NOT_ALLOWED, JSONObject().put("error", "请求方法不支持"))
        }
    }

    private fun query(session: IHTTPSession): Response {
        val trackingNumber = session.parameters["trackingNo"]?.firstOrNull()?.trim()?.uppercase().orEmpty()
        if (trackingNumber.isEmpty()) return json(Status.BAD_REQUEST, JSONObject().put("error", "缺少 trackingNo 参数"))
        val info = store.lookup(trackingNumber)
        return if (info == null) {
            json(Status.OK, JSONObject().put("found", false))
        } else {
            json(Status.OK, info.toJson().put("found", true))
        }
    }

    private fun push(session: IHTTPSession): Response {
        val contentType = session.headers["content-type"].orEmpty()
        require(contentType.startsWith("application/json", ignoreCase = true)) { "Content-Type 必须为 application/json" }
        val contentLength = session.headers["content-length"]?.toLongOrNull()
        require(contentLength == null || contentLength <= MAX_BODY_BYTES) { "请求内容过大，最大允许 1024 KB" }
        val files = HashMap<String, String>()
        session.parseBody(files)
        val body = files["postData"].orEmpty()
        require(body.toByteArray(Charsets.UTF_8).size <= MAX_BODY_BYTES) { "请求内容过大，最大允许 1024 KB" }
        val values = JSONArray(body)
        require(values.length() > 0) { "空数据" }
        require(values.length() <= MAX_ITEMS) { "单次最多推送 $MAX_ITEMS 条订单" }
        val now = System.currentTimeMillis()
        val items = (0 until values.length()).map { index ->
            OrderInfoRecord.fromJson(values.getJSONObject(index), now)
        }
        val tests = items.filter { it.isTest }
        val stored = store.upsert(items.filterNot { it.isTest })
        onReceived(stored + tests)
        return json(
            Status.OK,
            JSONObject()
                .put("ok", true)
                .put("count", stored.size)
                .put("testCount", tests.size),
        )
    }

    private fun json(status: Status, value: JSONObject): Response =
        newFixedLengthResponse(status, "application/json; charset=utf-8", value.toString())

    companion object {
        private const val MAX_BODY_BYTES = 1024 * 1024L
        private const val MAX_ITEMS = 200
    }
}
