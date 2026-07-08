import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 国际化/本地化服务，支持英文(默认)和中文切换
class LocaleService extends ChangeNotifier {
  static const _storageKey = 'app_lang';

  String _langCode = 'en';

  String get langCode => _langCode;
  bool get isZh => _langCode == 'zh';
  Locale get locale => Locale(_langCode);

  /// 获取翻译文本，支持 {key} 占位符替换
  String t(String key, {Map<String, String>? params}) {
    String val = (_strings[_langCode]?[key] ?? _strings['en']?[key]) ?? key;
    if (params != null) {
      for (final e in params.entries) {
        val = val.replaceAll('{${e.key}}', e.value);
      }
    }
    return val;
  }

  /// 从 SharedPreferences 加载语言设置
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _langCode = prefs.getString(_storageKey) ?? 'en';
    notifyListeners();
  }

  /// 设置语言代码
  Future<void> setLang(String code) async {
    if (code == _langCode) return;
    _langCode = code;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, code);
  }

  /// 切换语言（中/英）
  Future<void> toggle() => setLang(isZh ? 'en' : 'zh');

  // ── 静态翻译表 ──
  static const _strings = <String, Map<String, String>>{
    'en': {
      'app_title': 'USB Camera',
      'status_scanning': 'Scanning cameras...',
      'status_no_camera': 'No camera detected',
      'status_cameras_ready': '{n} camera(s) ready',
      'status_connecting': 'Connecting camera...',
      'status_conn_failed': 'USB camera connection failed',
      'status_scan_failed': 'Camera scan failed',
      'header_usb_count': 'USB {n} / Total {total}',
      'header_device_count': '{n} device(s)',
      'clear': 'Clear',
      'clear_title': 'Clear Media Library',
      'clear_content': 'Clear all {n} media files?',
      'cancel': 'Cancel',
      'confirm': 'Confirm',
      // 媒体库
      'gallery_title': '📁 Media',
      'gallery_empty': 'Photos and videos you capture will appear here',
      'delete_confirm_title': 'Delete Confirm',
      'delete_confirm_content': 'Delete this media file?',
      'delete': 'Delete',
      'deleted': '🗑️ Deleted',
      'delete_failed': 'Delete failed',
      'share': 'Share',
      'save_local': 'Save to device',
      'saved_local': 'Saved to device',
      'save_failed': 'Save failed',
      'resolution_set': 'Resolution set to {r}',
      'resolution_no_camera': 'Resolution set to {r} (no camera connected)',
      'photo_captured': 'Photo captured',
      'photo_failed': 'Photo capture failed',
      'recording_started': 'Recording started...',
      'video_saved': 'Video saved',
      'recording_failed': 'Recording failed',
      'recording_stop_failed': 'Failed to stop recording',
      'select_camera': 'Select camera',
      'scanning': 'Scanning...',
      'refresh_tooltip': 'Rescan cameras',
      'usb_detection': 'USB Detection',
      'no_camera_title': 'Connect Type-C USB Camera',
      'no_camera_desc': 'Plug in camera and tap refresh',
      'resolution': 'Resolution',
      'detection': 'Detection',
      'camera_label': 'Camera',
      'init_status': 'Initializing...',
      'camera_connected': '{tag} {label}',
      // 设备类型
      'device_usb': '✅ USB',
      'device_builtin': '💻 Built-in',
      'device_external': '🔌 External',
      'device_unknown': '📷 Camera',
      // USB 面板
      'usb_scanning': 'Scanning USB devices...',
      'usb_confirmed': '{n} USB camera(s) confirmed',
      'usb_no_match': '{n} USB device(s), no camera matched',
      'usb_not_detected': 'No USB camera detected',
      'usb_scanning_btn': 'Scanning...',
      // UVC 直连
      'uvc_connected': 'USB camera streaming',
      'uvc_open_failed': 'USB camera open failed',
      'uvc_no_device': 'No USB camera found',
      'uvc_capture_failed': 'USB capture failed',
      'uvc_no_recording': 'Recording not supported for UVC cameras',
      'uvc_source': 'USB (UVC)',
      'uvc_resolution_auto': 'Auto (UVC)',
      'uvc_mode': 'Quality',
      'uvc_mode_switch_failed': 'Failed to switch mode',
    },
    'zh': {
      'app_title': 'USB 摄像头',
      'status_scanning': '正在扫描摄像头...',
      'status_no_camera': '未检测到摄像头',
      'status_cameras_ready': '{n} 台摄像头就绪',
      'status_connecting': '正在连接摄像头...',
      'status_conn_failed': 'USB摄像头连接失败',
      'status_scan_failed': '摄像头扫描失败',
      'header_usb_count': '外接 {n} / 共 {total}',
      'header_device_count': '{n} 台设备',
      'clear': '清空',
      'clear_title': '清空媒体库',
      'clear_content': '确定要清空所有 {n} 个媒体文件吗？',
      'cancel': '取消',
      'confirm': '确定',
      // 媒体库
      'gallery_title': '📁 媒体库',
      'gallery_empty': '拍摄的照片和视频将显示在这里',
      'delete_confirm_title': '删除确认',
      'delete_confirm_content': '确定要删除这个媒体文件吗？',
      'delete': '删除',
      'deleted': '🗑️ 已删除',
      'delete_failed': '删除失败',
      'share': '分享',
      'save_local': '保存到本地',
      'saved_local': '已保存到本地',
      'save_failed': '保存失败',
      'resolution_set': '分辨率已切换为 {r}',
      'resolution_no_camera': '分辨率已设为 {r}（未连接摄像头）',
      'photo_captured': '照片已捕获',
      'photo_failed': '拍照失败',
      'recording_started': '开始录像...',
      'video_saved': '视频已保存',
      'recording_failed': '录像失败',
      'recording_stop_failed': '停止录像失败',
      'select_camera': '选择摄像头',
      'scanning': '正在扫描...',
      'refresh_tooltip': '重新扫描摄像头',
      'usb_detection': 'USB 检测',
      'no_camera_title': '连接 Type-C USB 摄像头',
      'no_camera_desc': '插入摄像头后点击刷新扫描',
      'resolution': '分辨率',
      'detection': '检测',
      'camera_label': '摄像头',
      'init_status': '正在初始化...',
      'camera_connected': '{tag} {label}',
      // 设备类型
      'device_usb': '✅ USB',
      'device_builtin': '💻 内置',
      'device_external': '🔌 外接',
      'device_unknown': '📷 摄像头',
      // USB 面板
      'usb_scanning': '正在扫描 USB 设备...',
      'usb_confirmed': '已确认 {n} 个 USB 摄像头',
      'usb_no_match': '{n} 个 USB 设备，未匹配到摄像头',
      'usb_not_detected': '未检测到 USB 摄像头',
      'usb_scanning_btn': '检测中...',
      // UVC 直连
      'uvc_connected': 'USB 摄像头已出图',
      'uvc_open_failed': 'USB 摄像头打开失败',
      'uvc_no_device': '未发现 USB 摄像头',
      'uvc_capture_failed': 'USB 拍照失败',
      'uvc_no_recording': 'UVC 摄像头暂不支持录像',
      'uvc_source': 'USB 直连',
      'uvc_resolution_auto': '自动(UVC)',
      'uvc_mode': '画质',
      'uvc_mode_switch_failed': '画质切换失败',
    },
  };
}
