/* Minimal Android EGL bring-up test (what SurfaceFlinger's RenderEngine needs first):
 * eglInitialize on the default display, list configs, pick RGBA8888 + ES2/ES3, make a pbuffer context current,
 * print GL_RENDERER, clear + glReadPixels. Exit 0 = PASS.
 * Build (host): tools/android-ndk-r29/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android33-clang \
 *   -O1 -Wall -o build/eglinit-android notes/scripts/eglinit.c -lEGL -lGLESv2
 * Run (in Waydroid as root): EGL_LOG_LEVEL=debug /data/local/tmp/eglinit-android ; Mesa logs go to logcat.
 */
#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <stdio.h>

int main(void)
{
   EGLDisplay dpy = eglGetDisplay(EGL_DEFAULT_DISPLAY);
   EGLint maj, min;
   if (!eglInitialize(dpy, &maj, &min)) {
      printf("eglInitialize FAILED 0x%x\n", eglGetError());
      return 1;
   }
   printf("EGL %d.%d vendor=%s\n", maj, min, eglQueryString(dpy, EGL_VENDOR));
   printf("EGL version: %s\n", eglQueryString(dpy, EGL_VERSION));

   EGLint n = 0;
   eglGetConfigs(dpy, NULL, 0, &n);
   printf("configs: %d\n", n);

   const EGLint attrs[] = { EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
                            EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
                            EGL_NONE };
   EGLConfig cfg;
   if (!eglChooseConfig(dpy, attrs, &cfg, 1, &n) || n < 1) {
      printf("eglChooseConfig RGBA8888/ES2/pbuffer: none (0x%x)\n", eglGetError());
      return 1;
   }
   const EGLint pb[] = { EGL_WIDTH, 64, EGL_HEIGHT, 64, EGL_NONE };
   EGLSurface s = eglCreatePbufferSurface(dpy, cfg, pb);
   const EGLint ca[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
   EGLContext c = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, ca);
   if (s == EGL_NO_SURFACE || c == EGL_NO_CONTEXT || !eglMakeCurrent(dpy, s, s, c)) {
      printf("surface/context/makecurrent FAILED 0x%x\n", eglGetError());
      return 1;
   }
   printf("GL_RENDERER: %s\nGL_VERSION: %s\n", glGetString(GL_RENDERER), glGetString(GL_VERSION));
   glClearColor(0.0f, 1.0f, 0.0f, 1.0f);
   glClear(GL_COLOR_BUFFER_BIT);
   unsigned char px[4] = { 0 };
   glReadPixels(0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
   printf("pixel: %u %u %u %u\n", px[0], px[1], px[2], px[3]);
   int ok = px[0] == 0 && px[1] == 255 && px[2] == 0;
   printf("RESULT: %s\n", ok ? "PASS" : "FAIL");
   eglTerminate(dpy);
   return ok ? 0 : 1;
}
