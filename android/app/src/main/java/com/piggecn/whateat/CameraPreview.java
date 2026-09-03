package com.piggecn.whateat;

import android.content.Context;
import android.hardware.Camera;
import android.view.SurfaceHolder;
import android.view.SurfaceView;

import java.io.IOException;

/** 扫码页的相机预览载体（旧 Camera API 足够，保持零第三方 UI 依赖） */
class CameraPreview extends SurfaceView implements SurfaceHolder.Callback {

    private SurfaceHolder holder;
    private Camera camera;

    CameraPreview(Context context) {
        super(context);
        holder = getHolder();
        holder.addCallback(this);
    }

    void setCamera(Camera cam) {
        camera = cam;
        try {
            camera.setPreviewDisplay(holder);
        } catch (IOException e) {
            camera = null;
        }
    }

    @Override
    public void surfaceCreated(SurfaceHolder h) {
        if (camera != null) {
            try {
                camera.setPreviewDisplay(h);
                camera.startPreview();
            } catch (Exception ignored) {
            }
        }
    }

    @Override
    public void surfaceChanged(SurfaceHolder h, int format, int w, int hgt) {
        if (h.getSurface() == null || camera == null) {
            return;
        }
        try {
            camera.stopPreview();
            camera.setPreviewDisplay(h);
            camera.startPreview();
        } catch (Exception ignored) {
        }
    }

    @Override
    public void surfaceDestroyed(SurfaceHolder h) {
    }
}
