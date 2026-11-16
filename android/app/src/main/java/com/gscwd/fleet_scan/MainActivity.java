package com.gscwd.fleet_scan;

import android.graphics.Bitmap;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.view.PixelCopy;
import android.view.SurfaceView;
import android.view.TextureView;
import android.view.View;
import android.view.ViewGroup;
import java.io.ByteArrayOutputStream;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    @Override
    public void configureFlutterEngine(FlutterEngine engine) {
        super.configureFlutterEngine(engine);
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),
                "com.gscwd.fleet_scan/preview").setMethodCallHandler((call, result) -> {
            if (!call.method.equals("capture")) {
                result.notImplemented();
                return;
            }
            Number width = call.argument("widthFraction");
            Number height = call.argument("heightFraction");
            final double widthFraction = width == null ? 1 : width.doubleValue();
            final double heightFraction = height == null ? 1 : height.doubleValue();
            View preview = findCameraPreview(getWindow().getDecorView());
            if (preview == null || preview.getWidth() == 0 || preview.getHeight() == 0) {
                result.success(null);
                return;
            }
            // A small preview is sufficient; preserve the real camera pixels.
            double scale = Math.min(1.0, 720.0 / Math.max(preview.getWidth(), preview.getHeight()));
            int w = Math.max(1, (int) (preview.getWidth() * scale));
            int h = Math.max(1, (int) (preview.getHeight() * scale));
            try {
                if (preview instanceof TextureView) {
                    Bitmap bitmap = ((TextureView) preview).getBitmap(w, h);
                    encodeCrop(bitmap, widthFraction, heightFraction, result);
                } else if (preview instanceof SurfaceView && Build.VERSION.SDK_INT >= 26) {
                    Bitmap bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
                    try {
                        PixelCopy.request((SurfaceView) preview, bitmap, status -> {
                            if (status == PixelCopy.SUCCESS) {
                                encodeCrop(bitmap, widthFraction, heightFraction, result);
                            } else {
                                bitmap.recycle();
                                result.success(null);
                            }
                        }, new Handler(Looper.getMainLooper()));
                    } catch (RuntimeException error) {
                        bitmap.recycle();
                        result.success(null);
                    }
                } else {
                    result.success(null);
                }
            } catch (RuntimeException error) {
                result.success(null);
            }
        });
    }

    private View findCameraPreview(View view) {
        // Flutter's own rendering surface is not the camera preview.
        if (!view.getClass().getName().startsWith("io.flutter.") &&
                (view instanceof TextureView || view instanceof SurfaceView)) {
            return view;
        }
        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            for (int index = 0; index < group.getChildCount(); index++) {
                View found = findCameraPreview(group.getChildAt(index));
                if (found != null) return found;
            }
        }
        return null;
    }

    private void encodeCrop(Bitmap bitmap, double widthFraction, double heightFraction,
            MethodChannel.Result result) {
        if (bitmap == null) {
            result.success(null);
            return;
        }
        // JPEG compression runs off the UI thread. Nothing is written to disk.
        new Thread(() -> {
            Bitmap crop = null;
            byte[] bytes = null;
            try {
                int w = Math.max(1, Math.min(bitmap.getWidth(),
                        (int) (bitmap.getWidth() * widthFraction)));
                int h = Math.max(1, Math.min(bitmap.getHeight(),
                        (int) (bitmap.getHeight() * heightFraction)));
                crop = Bitmap.createBitmap(bitmap,
                        (bitmap.getWidth() - w) / 2, (bitmap.getHeight() - h) / 2, w, h);
                ByteArrayOutputStream output = new ByteArrayOutputStream();
                if (crop.compress(Bitmap.CompressFormat.JPEG, 85, output)) {
                    bytes = output.toByteArray();
                }
            } catch (RuntimeException error) {
                // Keep the decoded ticket usable if the preview cannot be captured.
            } finally {
                if (crop != null && crop != bitmap) crop.recycle();
                bitmap.recycle();
            }
            final byte[] image = bytes;
            new Handler(Looper.getMainLooper()).post(() -> result.success(image));
        }, "fleet-scan-preview").start();
    }
}
