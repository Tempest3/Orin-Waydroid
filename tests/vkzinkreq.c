/* Android/Linux: what does the Vulkan loader + driver report that Zink's screen checks depend on?
 * Prints loader instance version, device apiVersion, and whether Zink's hard-required extensions
 * (those it needs unless core in the effective version) are advertised.
 * Build (host, Android): tools/android-ndk-r29/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android33-clang \
 *   -O1 -Wall -o build/vkzinkreq-android notes/scripts/vkzinkreq.c -lvulkan
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vulkan/vulkan.h>

static const char *req[] = { "VK_KHR_maintenance1", "VK_KHR_maintenance5", "VK_KHR_create_renderpass2",
                             "VK_KHR_dynamic_rendering", "VK_KHR_descriptor_update_template",
                             "VK_KHR_external_memory_fd", "VK_EXT_external_memory_dma_buf",
                             "VK_EXT_image_drm_format_modifier", "VK_EXT_physical_device_drm",
                             "VK_KHR_timeline_semaphore", "VK_EXT_robustness2", "VK_KHR_robustness2",
                             "VK_ANDROID_native_buffer", "VK_ANDROID_external_memory_android_hardware_buffer" };

#define V(v) VK_API_VERSION_MAJOR(v), VK_API_VERSION_MINOR(v), VK_API_VERSION_PATCH(v)

int main(void)
{
   uint32_t iv = 0;
   vkEnumerateInstanceVersion(&iv);
   printf("loader instance version: %u.%u.%u\n", V(iv));
   VkApplicationInfo app = { .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion = iv };
   VkInstanceCreateInfo ici = { .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &app };
   VkInstance inst;
   if (vkCreateInstance(&ici, NULL, &inst) != VK_SUCCESS) { printf("vkCreateInstance failed\n"); return 1; }
   uint32_t n = 1; VkPhysicalDevice pd;
   if (vkEnumeratePhysicalDevices(inst, &n, &pd) < 0 || !n) { printf("no physical device\n"); return 1; }
   VkPhysicalDeviceProperties p; vkGetPhysicalDeviceProperties(pd, &p);
   printf("device %s apiVersion %u.%u.%u\n", p.deviceName, V(p.apiVersion));
   uint32_t ne = 0; vkEnumerateDeviceExtensionProperties(pd, NULL, &ne, NULL);
   VkExtensionProperties *e = calloc(ne, sizeof(*e));
   vkEnumerateDeviceExtensionProperties(pd, NULL, &ne, e);
   printf("device extensions: %u\n", ne);
   for (unsigned i = 0; i < sizeof(req) / sizeof(req[0]); i++) {
      int have = 0;
      for (unsigned j = 0; j < ne; j++) have |= !strcmp(e[j].extensionName, req[i]);
      printf("  %-52s %s\n", req[i], have ? "yes" : "NO");
   }
   vkDestroyInstance(inst, NULL);
   return 0;
}
