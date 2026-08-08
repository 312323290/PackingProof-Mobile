import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/tracking_record_repository.dart';

/// 扫描记录列表页。
///
/// 直接从原有 recording_sessions 表读取数据，支持：
///  - 单页 10 条，分页；
///  - 日期筛选；
///  - 批量复制选中单号；
///  - 单条复制。
class TrackingRecordsScreen extends StatefulWidget {
  const TrackingRecordsScreen({super.key});

  @override
  State<TrackingRecordsScreen> createState() => _TrackingRecordsScreenState();
}

class _TrackingRecordsScreenState extends State<TrackingRecordsScreen> {
  final TrackingRecordRepository _repository = TrackingRecordRepository();
  final Set<String> _selectedNumbers = <String>{};

  List<TrackingRecord> _records = <TrackingRecord>[];
  int _total = 0;
  int _currentPage = 1;
  bool _loading = true;
  bool _selectMode = false;

  DateTime? _filterStart;
  DateTime? _filterEnd;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  Future<void> _loadPage() async {
    setState(() => _loading = true);
    try {
      final (List<TrackingRecord> records, int total) =
          await _repository.queryPage(
        page: _currentPage,
        start: _filterStart,
        end: _filterEnd,
      );
      if (!mounted) return;
      setState(() {
        _records = records;
        _total = total;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  int get _totalPages => (_total / TrackingRecordRepository.pageSize).ceil();

  Future<void> _pickDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _filterStart != null && _filterEnd != null
          ? DateTimeRange(start: _filterStart!, end: _filterEnd!)
          : null,
    );
    if (picked == null) return;
    setState(() {
      _filterStart = picked.start;
      _filterEnd = picked.end;
      _currentPage = 1;
      _selectedNumbers.clear();
    });
    _loadPage();
  }

  Future<void> _clearFilter() async {
    setState(() {
      _filterStart = null;
      _filterEnd = null;
      _currentPage = 1;
      _selectedNumbers.clear();
    });
    _loadPage();
  }

  Future<void> _copySingle(String number) async {
    await Clipboard.setData(ClipboardData(text: number));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制：$number'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _batchCopy() async {
    if (_selectedNumbers.isEmpty) return;
    final List<String> numbers = _records
        .where((r) => _selectedNumbers.contains(r.trackingNumber))
        .map((r) => r.trackingNumber)
        .toList();
    await Clipboard.setData(ClipboardData(text: numbers.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已批量复制 ${numbers.length} 条记录'),
        duration: const Duration(seconds: 2),
      ),
    );
    setState(() {
      _selectMode = false;
      _selectedNumbers.clear();
    });
  }

  void _toggleSelectAll() {
    if (_selectedNumbers.length == _records.length) {
      _selectedNumbers.clear();
    } else {
      for (final TrackingRecord r in _records) {
        _selectedNumbers.add(r.trackingNumber);
      }
    }
    setState(() {});
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('扫描记录'),
        actions: <Widget>[
          if (_selectMode) ...[
            IconButton(
              icon: const Icon(Icons.select_all),
              onPressed: _toggleSelectAll,
              tooltip: '全选/取消',
            ),
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: _selectedNumbers.isEmpty ? null : _batchCopy,
              tooltip: '批量复制',
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _selectMode = false;
                  _selectedNumbers.clear();
                });
              },
              tooltip: '取消选择',
            ),
          ] else
            IconButton(
              icon: const Icon(Icons.checklist),
              onPressed: () => setState(() => _selectMode = true),
              tooltip: '选择模式',
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _buildDateFilterBar(),
          Expanded(child: _buildRecordList()),
          if (_totalPages > 1) _buildPaginationBar(),
        ],
      ),
    );
  }

  Widget _buildDateFilterBar() {
    final String label;
    if (_filterStart != null && _filterEnd != null) {
      label = '${_filterStart!.year}-${_filterStart!.month.toString().padLeft(2, '0')}-${_filterStart!.day.toString().padLeft(2, '0')}'
          ' ~ '
          '${_filterEnd!.year}-${_filterEnd!.month.toString().padLeft(2, '0')}-${_filterEnd!.day.toString().padLeft(2, '0')}';
    } else {
      label = '全部记录';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: <Widget>[
          const Icon(Icons.date_range, size: 20),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _pickDateRange,
            child: Text(label, style: const TextStyle(fontSize: 14)),
          ),
          if (_filterStart != null || _filterEnd != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _clearFilter,
              child: const Icon(Icons.clear, size: 18, color: Colors.grey),
            ),
          ],
          const Spacer(),
          Text('共 $_total 条', style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildRecordList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_records.isEmpty) {
      return const Center(child: Text('暂无扫描记录'));
    }
    return ListView.builder(
      itemCount: _records.length,
      itemBuilder: (BuildContext context, int index) {
        final TrackingRecord record = _records[index];
        final bool selected = _selectedNumbers.contains(record.trackingNumber);
        return ListTile(
          leading: _selectMode
              ? Checkbox(
                  value: selected,
                  onChanged: (bool? checked) {
                    setState(() {
                      if (checked == true) {
                        _selectedNumbers.add(record.trackingNumber);
                      } else {
                        _selectedNumbers.remove(record.trackingNumber);
                      }
                    });
                  },
                )
              : const Icon(Icons.qr_code),
          title: Text(
            record.trackingNumber,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          subtitle: Text(
            _formatDate(record.recognizedAt),
            style: const TextStyle(fontSize: 12),
          ),
          trailing: _selectMode
              ? null
              : IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: () => _copySingle(record.trackingNumber),
                  tooltip: '复制单号',
                ),
          onTap: _selectMode
              ? () {
                  setState(() {
                    if (_selectedNumbers.contains(record.trackingNumber)) {
                      _selectedNumbers.remove(record.trackingNumber);
                    } else {
                      _selectedNumbers.add(record.trackingNumber);
                    }
                  });
                }
              : () => _copySingle(record.trackingNumber),
        );
      },
    );
  }

  Widget _buildPaginationBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _currentPage > 1
                ? () {
                    setState(() {
                      _currentPage--;
                      _selectedNumbers.clear();
                    });
                    _loadPage();
                  }
                : null,
          ),
          Text('第 $_currentPage / $_totalPages 页'),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _currentPage < _totalPages
                ? () {
                    setState(() {
                      _currentPage++;
                      _selectedNumbers.clear();
                    });
                    _loadPage();
                  }
                : null,
          ),
        ],
      ),
    );
  }
}