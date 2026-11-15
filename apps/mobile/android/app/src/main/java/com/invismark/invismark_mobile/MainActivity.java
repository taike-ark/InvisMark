package com.invismark.invismark_mobile;

import android.app.Activity;
import android.content.ContentValues;
import android.content.Intent;
import android.content.SharedPreferences;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;
import android.provider.OpenableColumns;
import android.util.Log;

import androidx.core.content.FileProvider;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

/**
 * Android 宿主 Activity + 原生媒体桥（零第三方插件）。
 *
 * 通道：invismark/media
 *   pickImage()            -> true           打开系统相册（结果落盘，等 Dart 轮询）
 *   capturePhoto()         -> true           打开相机（同上）
 *   consumePendingPick()   -> {bytes,name}?  取走并清除上一次选图结果
 *   saveToGallery(bytes, name) -> String     保存到系统相册
 *   shareBytes(bytes, name)    -> Boolean    系统分享
 *   getPrefs()             -> Map            读取设置
 *   setPref(key, value)    -> Boolean        写设置
 *
 * 为什么选图结果不直接用 MethodChannel.Result 回传：
 * 部分 ROM（如 vivo）在从相册返回时会重建 Activity 甚至 FlutterEngine，
 * 旧的 Result 回调会失效，表现为「选完图 App 闪退 / 卡住」。
 * 这里改成「落盘 + 轮询」，即使 Activity 重建也能拿到图片。
 */
public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "invismark/media";
    private static final int REQ_PICK = 1001;
    private static final int REQ_CAMERA = 1002;
    private static final String TAG = "InvisMark";

    private MethodChannel channel;
    private Uri cameraUri;
    private String cameraName;

    @Override
    public void configureFlutterEngine(FlutterEngine engine) {
        super.configureFlutterEngine(engine);
        channel = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(this::onMethodCall);
    }

    private void onMethodCall(MethodCall call, MethodChannel.Result result) {
        switch (call.method) {
            case "pickImage":
                startPick(result);
                break;
            case "capturePhoto":
                startCapture(result);
                break;
            case "consumePendingPick":
                result.success(consumePendingPick());
                break;
            case "saveToGallery":
                saveToGallery(call.argument("bytes"), call.argument("name"), result);
                break;
            case "shareBytes":
                shareBytes(call.argument("bytes"), call.argument("name"), result);
                break;
            case "getPrefs":
                result.success(prefs().getAll());
                break;
            case "setPref":
                prefs().edit()
                        .putString(call.argument("key"), call.argument("value"))
                        .apply();
                result.success(true);
                break;
            default:
                result.notImplemented();
        }
    }

    private SharedPreferences prefs() {
        return getSharedPreferences("invismark", MODE_PRIVATE);
    }

    // ── 选图 / 拍照 ───────────────────────────────────────────────

    private void startPick(MethodChannel.Result result) {
        try {
            Log.i(TAG, "startPick");
            clearPendingPick();
            Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
            intent.setType("image/*");
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            startActivityForResult(Intent.createChooser(intent, "选择图片"), REQ_PICK);
            result.success(true);
        } catch (Exception e) {
            result.error("pick_failed", "无法打开相册：" + e.getMessage(), null);
        }
    }

    private void startCapture(MethodChannel.Result result) {
        try {
            Log.i(TAG, "startCapture");
            clearPendingPick();
            cameraName = "invismark-" + timestamp() + ".jpg";
            File dir = new File(getCacheDir(), "camera");
            if (!dir.exists() && !dir.mkdirs()) {
                throw new IllegalStateException("无法创建相机缓存目录");
            }
            File photo = new File(dir, cameraName);
            cameraUri = FileProvider.getUriForFile(
                    this, getPackageName() + ".fileprovider", photo);
            Intent intent = new Intent(MediaStore.ACTION_IMAGE_CAPTURE);
            intent.putExtra(MediaStore.EXTRA_OUTPUT, cameraUri);
            intent.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
            startActivityForResult(intent, REQ_CAMERA);
            result.success(true);
        } catch (Exception e) {
            result.error("camera_failed", "无法打开相机：" + e.getMessage(), null);
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        Log.i(TAG, "onActivityResult req=" + requestCode + " res=" + resultCode
                + " hasData=" + (data != null));
        if (requestCode != REQ_PICK && requestCode != REQ_CAMERA) {
            return;
        }
        if (resultCode != Activity.RESULT_OK) {
            clearPendingPick();
            return;
        }
        try {
            Uri uri;
            String name;
            if (requestCode == REQ_PICK) {
                uri = data == null ? null : data.getData();
                if (uri == null && data != null && data.getClipData() != null
                        && data.getClipData().getItemCount() > 0) {
                    uri = data.getClipData().getItemAt(0).getUri();
                }
                name = displayName(uri);
            } else {
                uri = cameraUri;
                name = cameraName;
            }
            if (uri == null) {
                Log.w(TAG, "onActivityResult: uri is null");
                return;
            }
            byte[] bytes = readBytes(uri);
            if (bytes.length == 0) {
                Log.w(TAG, "onActivityResult: empty bytes");
                return;
            }
            writePendingPick(bytes, name == null ? "image-" + timestamp() + ".jpg" : name);
            Log.i(TAG, "pending pick stored bytes=" + bytes.length + " name=" + name);
        } catch (Exception e) {
            Log.e(TAG, "onActivityResult failed", e);
        }
    }

    private File pendingDir() {
        File dir = new File(getCacheDir(), "picked");
        if (!dir.exists() && !dir.mkdirs()) {
            Log.w(TAG, "cannot create pending dir");
        }
        return dir;
    }

    private void writePendingPick(byte[] bytes, String name) {
        try {
            File dir = pendingDir();
            try (FileOutputStream out = new FileOutputStream(new File(dir, "last.bin"))) {
                out.write(bytes);
            }
            try (FileOutputStream out = new FileOutputStream(new File(dir, "last.name"))) {
                out.write(name.getBytes("UTF-8"));
            }
        } catch (Exception e) {
            Log.e(TAG, "writePendingPick failed", e);
        }
    }

    private Map<String, Object> consumePendingPick() {
        try {
            File dir = pendingDir();
            File bin = new File(dir, "last.bin");
            File nameFile = new File(dir, "last.name");
            if (!bin.exists() || bin.length() == 0) {
                return null;
            }
            byte[] bytes;
            try (InputStream in = new java.io.FileInputStream(bin);
                 ByteArrayOutputStream out = new ByteArrayOutputStream()) {
                byte[] buffer = new byte[64 * 1024];
                int read;
                while ((read = in.read(buffer)) != -1) {
                    out.write(buffer, 0, read);
                }
                bytes = out.toByteArray();
            }
            String name = "image.png";
            if (nameFile.exists()) {
                try (InputStream in = new java.io.FileInputStream(nameFile);
                     ByteArrayOutputStream out = new ByteArrayOutputStream()) {
                    byte[] buffer = new byte[1024];
                    int read;
                    while ((read = in.read(buffer)) != -1) {
                        out.write(buffer, 0, read);
                    }
                    name = out.toString("UTF-8").trim();
                }
            }
            bin.delete();
            nameFile.delete();
            Map<String, Object> payload = new HashMap<>();
            payload.put("bytes", bytes);
            payload.put("name", name.isEmpty() ? "image.png" : name);
            Log.i(TAG, "consumePendingPick bytes=" + bytes.length);
            return payload;
        } catch (Exception e) {
            Log.e(TAG, "consumePendingPick failed", e);
            return null;
        }
    }

    private void clearPendingPick() {
        File dir = new File(getCacheDir(), "picked");
        new File(dir, "last.bin").delete();
        new File(dir, "last.name").delete();
    }

    // ── 保存 / 分享 ───────────────────────────────────────────────

    private void saveToGallery(byte[] bytes, String name, MethodChannel.Result result) {
        if (bytes == null || bytes.length == 0) {
            result.error("bad_args", "图片数据为空", null);
            return;
        }
        try {
            String fileName = safeName(name);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ContentValues values = new ContentValues();
                values.put(MediaStore.Images.Media.DISPLAY_NAME, fileName);
                values.put(MediaStore.Images.Media.MIME_TYPE, mimeOf(fileName));
                values.put(MediaStore.Images.Media.RELATIVE_PATH,
                        Environment.DIRECTORY_PICTURES + "/InvisMark");
                values.put(MediaStore.Images.Media.IS_PENDING, 1);
                Uri uri = getContentResolver().insert(
                        MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values);
                if (uri == null) {
                    throw new IllegalStateException("MediaStore 插入失败");
                }
                try (OutputStream out = getContentResolver().openOutputStream(uri)) {
                    if (out == null) {
                        throw new IllegalStateException("无法写入相册");
                    }
                    out.write(bytes);
                }
                values.clear();
                values.put(MediaStore.Images.Media.IS_PENDING, 0);
                getContentResolver().update(uri, values, null, null);
                result.success("Pictures/InvisMark/" + fileName);
                return;
            }
            File dir = new File(Environment.getExternalStoragePublicDirectory(
                    Environment.DIRECTORY_PICTURES), "InvisMark");
            if (!dir.exists() && !dir.mkdirs()) {
                throw new IllegalStateException("无法创建相册目录");
            }
            File outFile = new File(dir, fileName);
            try (FileOutputStream out = new FileOutputStream(outFile)) {
                out.write(bytes);
            }
            sendBroadcast(new Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE,
                    Uri.fromFile(outFile)));
            result.success(outFile.getAbsolutePath());
        } catch (Exception e) {
            result.error("save_failed", "保存失败：" + e.getMessage(), null);
        }
    }

    private void shareBytes(byte[] bytes, String name, MethodChannel.Result result) {
        if (bytes == null || bytes.length == 0) {
            result.error("bad_args", "图片数据为空", null);
            return;
        }
        try {
            File dir = new File(getCacheDir(), "share");
            if (!dir.exists() && !dir.mkdirs()) {
                throw new IllegalStateException("无法创建分享缓存目录");
            }
            File file = new File(dir, safeName(name));
            try (FileOutputStream out = new FileOutputStream(file)) {
                out.write(bytes);
            }
            Uri uri = FileProvider.getUriForFile(
                    this, getPackageName() + ".fileprovider", file);
            Intent intent = new Intent(Intent.ACTION_SEND);
            intent.setType(mimeOf(file.getName()));
            intent.putExtra(Intent.EXTRA_STREAM, uri);
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            startActivity(Intent.createChooser(intent, "分享带水印图片"));
            result.success(true);
        } catch (Exception e) {
            result.error("share_failed", "分享失败：" + e.getMessage(), null);
        }
    }

    // ── 工具 ─────────────────────────────────────────────────────

    private byte[] readBytes(Uri uri) throws Exception {
        try (InputStream in = getContentResolver().openInputStream(uri);
             ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            if (in == null) {
                throw new IllegalStateException("无法打开输入流");
            }
            byte[] buffer = new byte[64 * 1024];
            int read;
            while ((read = in.read(buffer)) != -1) {
                out.write(buffer, 0, read);
            }
            return out.toByteArray();
        }
    }

    private String displayName(Uri uri) {
        if (uri == null) {
            return null;
        }
        try (Cursor cursor = getContentResolver().query(
                uri, new String[]{OpenableColumns.DISPLAY_NAME}, null, null, null)) {
            if (cursor != null && cursor.moveToFirst()) {
                int index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                if (index >= 0) {
                    return cursor.getString(index);
                }
            }
        } catch (Exception ignored) {
            // 部分提供方不支持查询，退回默认名
        }
        return null;
    }

    private static String timestamp() {
        return new SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(new Date());
    }

    private static String safeName(String name) {
        String base = (name == null || name.trim().isEmpty())
                ? "invismark-" + timestamp() + ".png"
                : name.trim();
        base = base.replaceAll("[\\\\/:*?\"<>|]", "_");
        return base;
    }

    private static String mimeOf(String fileName) {
        String lower = fileName == null ? "" : fileName.toLowerCase(Locale.US);
        if (lower.endsWith(".png")) {
            return "image/png";
        }
        if (lower.endsWith(".webp")) {
            return "image/webp";
        }
        return "image/jpeg";
    }
}
