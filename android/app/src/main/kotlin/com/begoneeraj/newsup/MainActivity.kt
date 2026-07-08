package com.begoneeraj.newsup

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode

class MainActivity : FlutterActivity() {
    // Default SurfaceView-backed rendering ("surface" mode) renders solid
    // black on some MIUI/Android 10 devices (observed on Redmi 8A, Adreno
    // 308) where the surface never receives valid dimensions. TextureView
    // mode is slightly less performant but avoids this failure mode.
    override fun getRenderMode(): RenderMode = RenderMode.texture
}
