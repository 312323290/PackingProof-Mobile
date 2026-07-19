# mobile-backup-v1

PackingProof-Mobile 使用电脑二维码中的局域网地址和访问密钥连接电脑。二维码格式为：

```text
http://192.168.1.20:5280/?key=<至少16字符的访问密钥>
```

手机仅接受私有 IPv4、IPv6 ULA 或链路本地地址。所有请求都携带 `X-EPM-Access-Key`，正文 JSON 使用 UTF-8。

## 能力协商

`GET /api/mobile-backup/capabilities`

```json
{
  "protocol": "packing-proof-backup",
  "version": 1,
  "computerId": "stable-computer-id",
  "computerName": "仓库电脑",
  "maxChunkBytes": 4194304,
  "acceptedContainers": ["mp4"],
  "acceptedVideoCodecs": ["h264", "h265"]
}
```

## 创建或恢复上传

`POST /api/mobile-backup/uploads` 按文件 SHA256 幂等创建任务。响应：

```json
{
  "uploadId": "server-upload-id",
  "offset": 0,
  "chunkSize": 4194304,
  "completed": false
}
```

请求包含文件名、大小、SHA256、容器、视频编码，以及引用该物理文件的所有逻辑录像、面单号、时间范围和标记。

## 分块与完成

- `PUT /api/mobile-backup/uploads/{uploadId}/chunks`
- 请求头：`Content-Range: bytes <start>-<end>/<total>`、`X-Chunk-SHA256`
- 响应：`{"nextOffset": <服务端已确认偏移>}`
- `POST /api/mobile-backup/uploads/{uploadId}/complete` 提交完整 SHA256 和逻辑录像元数据

`401/403` 表示需要重新配对，`404` 表示电脑端不支持该协议，`409` 表示客户端应按服务端偏移重新同步；超时和 `5xx` 可重试。
