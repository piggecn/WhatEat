package com.piggecn.whateat;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.hardware.Camera;
import android.media.Ringtone;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.HandlerThread;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.TextView;

import com.google.zxing.BinaryBitmap;
import com.google.zxing.DecodeHintType;
import com.google.zxing.MultiFormatReader;
import com.google.zxing.PlanarYUVLuminanceSource;
import com.google.zxing.Result;
import com.google.zxing.common.HybridBinarizer;

import java.util.EnumMap;
import java.util.Map;

/**
 * 极简二维码扫描：Camera 预览帧 → zxing 解码，成功即返回文本。
 * （不引第三方扫描 UI，只依赖 zxing core 纯解码，保持 APK 精简）
 */
public class ScanActivity extends Activity implements Camera.PreviewCallback {

    private Camera camera;
    private CameraPreview preview;
    private HandlerThread decodeThread;
    private Handler decodeHandler;
    private MultiFormatReader reader;
    private volatile boolean decoding;
    private volatile boolean done;
    private int previewWidth;
    private int previewHeight;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.BLACK);

        preview = new CameraPreview(this);
        root.addView(preview, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        TextView hint = new TextView(this);
        hint.setText("对准「关于页 → 手机客户端配置」的二维码");
        hint.setTextColor(Color.WHITE);
        hint.setTextSize(14);
        hint.setBackgroundColor(Color.argb(150, 0, 0, 0));
        hint.setGravity(Gravity.CENTER);
        FrameLayout.LayoutParams hintLp = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        hintLp.gravity = Gravity.BOTTOM;
        hintLp.setMargins(dp(12), 0, dp(12), dp(24));
        root.addView(hint, hintLp);

        Button cancel = new Button(this);
        cancel.setText("取消");
        cancel.setAllCaps(false);
        FrameLayout.LayoutParams cancelLp = new FrameLayout.LayoutParams(dp(88), dp(40));
        cancelLp.gravity = Gravity.TOP | Gravity.END;
        cancelLp.setMargins(0, dp(12), dp(12), 0);
        root.addView(cancel, cancelLp);
        cancel.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                finishWith(null);
            }
        });

        setContentView(root);

        decodeThread = new HandlerThread("qr-decode");
        decodeThread.start();
        decodeHandler = new Handler(decodeThread.getLooper());

        reader = new MultiFormatReader();
        Map<DecodeHintType, Object> hints = new EnumMap<>(DecodeHintType.class);
        hints.put(DecodeHintType.POSSIBLE_FORMATS,
                java.util.Collections.singletonList(com.google.zxing.BarcodeFormat.QR_CODE));
        hints.put(DecodeHintType.CHARACTER_SET, "UTF-8");
        reader.setHints(hints);
    }

    @Override
    protected void onResume() {
        super.onResume();
        safeOpenCamera();
    }

    private void safeOpenCamera() {
        try {
            camera = Camera.open();
            Camera.Parameters params = camera.getParameters();
            Camera.Size size = params.getPreviewSize();
            previewWidth = size.width;
            previewHeight = size.height;
            params.setFocusMode(Camera.Parameters.FOCUS_MODE_CONTINUOUS_PICTURE);
            camera.setParameters(params);
            preview.setCamera(camera);
            camera.setPreviewCallback(this);
            camera.startPreview();
        } catch (Exception e) {
            finishWith(null);
        }
    }

    @Override
    public void onPreviewFrame(byte[] data, Camera cam) {
        if (decoding || done || data == null) {
            return;
        }
        decoding = true;
        final byte[] copy = data.clone();
        final int w = previewWidth;
        final int h = previewHeight;
        decodeHandler.post(new Runnable() {
            @Override
            public void run() {
                Result decoded = null;
                try {
                    PlanarYUVLuminanceSource source =
                            new PlanarYUVLuminanceSource(copy, w, h, 0, 0, w, h, false);
                    BinaryBitmap bitmap =
                            new BinaryBitmap(new HybridBinarizer(source));
                    decoded = reader.decodeWithState(bitmap);
                } catch (Exception ignored) {
                }
                if (decoded != null && !done) {
                    final String text = decoded.getText();
                    runOnUiThread(new Runnable() {
                        @Override
                        public void run() {
                            finishWith(text);
                        }
                    });
                }
                decoding = false;
            }
        });
    }

    private void finishWith(String text) {
        if (done) {
            return;
        }
        done = true;
        releaseCamera();
        if (text != null && !text.trim().isEmpty()) {
            try {
                Uri notification = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION);
                Ringtone r = RingtoneManager.getRingtone(getApplicationContext(), notification);
                r.play();
            } catch (Exception ignored) {
            }
            Intent data = new Intent();
            data.putExtra("text", text);
            setResult(RESULT_OK, data);
        } else {
            setResult(RESULT_CANCELED);
        }
        finish();
    }

    private void releaseCamera() {
        try {
            if (camera != null) {
                camera.setPreviewCallback(null);
                camera.stopPreview();
                camera.release();
            }
        } catch (Exception ignored) {
        }
        camera = null;
    }

    @Override
    protected void onPause() {
        super.onPause();
        releaseCamera();
    }

    @Override
    protected void onDestroy() {
        releaseCamera();
        if (decodeThread != null) {
            decodeThread.quitSafely();
        }
        super.onDestroy();
    }

    private int dp(int v) {
        return Math.round(v * getResources().getDisplayMetrics().density);
    }
}
