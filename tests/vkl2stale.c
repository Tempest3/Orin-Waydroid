/* GPU/CPU cache-coherency stress test, per host-visible memory type (L2-staleness audit, 2026-11-26).
 * Each iteration, for buffers src/dst in the memory type under test:
 *   CPU: src[i] = it*N + i, dst[i] = 0xDEADBEEF   (+ vkFlushMappedMemoryRanges if non-coherent)
 *   GPU: compute shader dst[i] = src[i]           (buffer device address, push constants)
 *   CPU: (vkInvalidateMappedMemoryRanges if non-coherent) check dst[i]
 * The previous iteration's copy leaves src/dst lines warm in GPU L2 and CPU caches, so staleness shows as:
 *   dst == previous src value  → GPU read a stale copy of CPU-written data   ("gpu-stale")
 *   dst == 0xDEADBEEF          → CPU didn't see the GPU write               ("cpu-stale")
 * Build (host):
 *   glslangValidator -V --target-env vulkan1.2 --vn l2copy_spv -o build/l2copy_spv.h notes/scripts/vkl2stale.comp
 *   build/mesa-nvk-aarch64-tools/cc -O1 -Wall -Ibuild -o build/vkl2stale notes/scripts/vkl2stale.c \
 *     src/sysroot-jetson/usr/lib/aarch64-linux-gnu/libvulkan.so.1.3.275 -lm
 * Run (on Jetson): NVK_ON_NVGPU=1 NVK_I_WANT_A_BROKEN_VULKAN_DRIVER=1 VK_DRIVER_FILES=~/mesa-nvk/nvk_icd.json \
 *   ./vkl2stale [iterations] [words]
 */
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vulkan/vulkan.h>
#include "l2copy_spv.h"

#define CHECK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { \
   fprintf(stderr, "%s:%d %s = %d\n", __FILE__, __LINE__, #x, r_); exit(1); } } while (0)

struct buf { VkBuffer b; VkDeviceMemory m; uint32_t *p; VkDeviceAddress a; };

static VkDevice dev;
static VkPhysicalDeviceMemoryProperties mp;

static void make_buf(struct buf *o, uint32_t type, VkDeviceSize size)
{
   VkBufferCreateInfo bi = { .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .size = size,
      .usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT };
   CHECK(vkCreateBuffer(dev, &bi, NULL, &o->b));
   VkMemoryRequirements req; vkGetBufferMemoryRequirements(dev, o->b, &req);
   VkMemoryAllocateFlagsInfo fi = { .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_FLAGS_INFO,
      .flags = VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT };
   VkMemoryAllocateInfo ai = { .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .pNext = &fi,
      .allocationSize = req.size, .memoryTypeIndex = type };
   CHECK(vkAllocateMemory(dev, &ai, NULL, &o->m));
   CHECK(vkBindBufferMemory(dev, o->b, o->m, 0));
   CHECK(vkMapMemory(dev, o->m, 0, VK_WHOLE_SIZE, 0, (void **)&o->p));
   VkBufferDeviceAddressInfo dai = { .sType = VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO, .buffer = o->b };
   o->a = vkGetBufferDeviceAddress(dev, &dai);
}

static void free_buf(struct buf *o)
{
   vkUnmapMemory(dev, o->m); vkDestroyBuffer(dev, o->b, NULL); vkFreeMemory(dev, o->m, NULL);
}

int main(int argc, char **argv)
{
   setvbuf(stdout, NULL, _IOLBF, 0);
   const uint32_t iters = argc > 1 ? atoi(argv[1]) : 300;
   const uint32_t n = argc > 2 ? atoi(argv[2]) : 65536;   /* 256 KiB: fits in L2 */
   const VkDeviceSize size = (VkDeviceSize)n * 4;

   VkApplicationInfo app = { .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion = VK_API_VERSION_1_3 };
   VkInstanceCreateInfo ici = { .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &app };
   VkInstance inst; CHECK(vkCreateInstance(&ici, NULL, &inst));
   uint32_t npd = 1; VkPhysicalDevice pd;
   if (vkEnumeratePhysicalDevices(inst, &npd, &pd) < 0 || !npd) { puts("no device"); return 1; }
   VkPhysicalDeviceProperties props; vkGetPhysicalDeviceProperties(pd, &props);
   vkGetPhysicalDeviceMemoryProperties(pd, &mp);
   printf("device %s, nonCoherentAtomSize %" PRIu64 ", %u iters x %u words\n",
          props.deviceName, props.limits.nonCoherentAtomSize, iters, n);

   float prio = 1;
   VkDeviceQueueCreateInfo qci = { .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
      .queueFamilyIndex = 0, .queueCount = 1, .pQueuePriorities = &prio };
   VkPhysicalDeviceVulkan12Features f12 = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
      .bufferDeviceAddress = VK_TRUE };
   VkDeviceCreateInfo dci = { .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, .pNext = &f12,
      .queueCreateInfoCount = 1, .pQueueCreateInfos = &qci };
   CHECK(vkCreateDevice(pd, &dci, NULL, &dev));
   VkQueue q; vkGetDeviceQueue(dev, 0, 0, &q);

   VkShaderModuleCreateInfo smi = { .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
      .codeSize = sizeof(l2copy_spv), .pCode = l2copy_spv };
   VkShaderModule sm; CHECK(vkCreateShaderModule(dev, &smi, NULL, &sm));
   VkPushConstantRange pcr = { VK_SHADER_STAGE_COMPUTE_BIT, 0, 20 };
   VkPipelineLayoutCreateInfo pli = { .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
      .pushConstantRangeCount = 1, .pPushConstantRanges = &pcr };
   VkPipelineLayout pl; CHECK(vkCreatePipelineLayout(dev, &pli, NULL, &pl));
   VkComputePipelineCreateInfo cpi = { .sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
      .stage = { .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                 .stage = VK_SHADER_STAGE_COMPUTE_BIT, .module = sm, .pName = "main" },
      .layout = pl };
   VkPipeline pipe; CHECK(vkCreateComputePipelines(dev, VK_NULL_HANDLE, 1, &cpi, NULL, &pipe));

   VkCommandPoolCreateInfo cpci = { .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
      .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT };
   VkCommandPool pool; CHECK(vkCreateCommandPool(dev, &cpci, NULL, &pool));
   VkCommandBufferAllocateInfo cbai = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
      .commandPool = pool, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1 };
   VkCommandBuffer cb; CHECK(vkAllocateCommandBuffers(dev, &cbai, &cb));
   VkFenceCreateInfo fci = { .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO };
   VkFence fence; CHECK(vkCreateFence(dev, &fci, NULL, &fence));

   int bad_total = 0;
   for (uint32_t t = 0; t < mp.memoryTypeCount; t++) {
      VkMemoryPropertyFlags fl = mp.memoryTypes[t].propertyFlags;
      if (!(fl & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT))
         continue;
      const int coherent = !!(fl & VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
      struct buf src, dst;
      make_buf(&src, t, size); make_buf(&dst, t, size);
      VkMappedMemoryRange rs = { .sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE, .memory = src.m, .size = VK_WHOLE_SIZE };
      VkMappedMemoryRange rd = rs; rd.memory = dst.m;
      uint64_t gpu_stale = 0, cpu_stale = 0, other = 0, junk = 0, age_hist[16] = { 0 };
      uint32_t bad_iters = 0;

      for (uint32_t it = 0; it < iters; it++) {
         for (uint32_t i = 0; i < n; i++) { src.p[i] = it * n + i; dst.p[i] = 0xDEADBEEF; }
         if (!coherent) { VkMappedMemoryRange r[2] = { rs, rd }; CHECK(vkFlushMappedMemoryRanges(dev, 2, r)); }

         CHECK(vkResetCommandBuffer(cb, 0));
         VkCommandBufferBeginInfo bi = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT };
         CHECK(vkBeginCommandBuffer(cb, &bi));
         VkMemoryBarrier hb = { .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER,
            .srcAccessMask = VK_ACCESS_HOST_WRITE_BIT, .dstAccessMask = VK_ACCESS_SHADER_READ_BIT };
         vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_HOST_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 1, &hb, 0, NULL, 0, NULL);
         vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_COMPUTE, pipe);
         struct { uint64_t s, d; uint32_t n; } __attribute__((packed)) pc = { src.a, dst.a, n };
         vkCmdPushConstants(cb, pl, VK_SHADER_STAGE_COMPUTE_BIT, 0, 20, &pc);
         vkCmdDispatch(cb, (n + 255) / 256, 1, 1);
         VkMemoryBarrier db = { .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER,
            .srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT, .dstAccessMask = VK_ACCESS_HOST_READ_BIT };
         vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_HOST_BIT, 0, 1, &db, 0, NULL, 0, NULL);
         CHECK(vkEndCommandBuffer(cb));
         VkSubmitInfo si = { .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO, .commandBufferCount = 1, .pCommandBuffers = &cb };
         CHECK(vkQueueSubmit(q, 1, &si, fence));
         CHECK(vkWaitForFences(dev, 1, &fence, VK_TRUE, 5000000000ull));
         CHECK(vkResetFences(dev, 1, &fence));
         if (!coherent) CHECK(vkInvalidateMappedMemoryRanges(dev, 1, &rd));

         uint32_t bad = 0;
         for (uint32_t i = 0; i < n; i++) {
            uint32_t v = dst.p[i], want = it * n + i;
            if (v == want) continue;
            bad++;
            if (v == 0xDEADBEEF) cpu_stale++;
            else if (it > 0 && v == (it - 1) * n + i) gpu_stale++;
            else other++;
            /* age histogram: value from iteration (v - i) / n */
            if (v != 0xDEADBEEF && v >= i && (v - i) % n == 0 && (v - i) / n < it) {
               uint32_t age = it - (v - i) / n;
               age_hist[age < 15 ? age : 15]++;
            } else if (v != 0xDEADBEEF) junk++;
         }
         bad_iters += bad != 0;
      }
      printf("type %u [%s%s%s%s] heap %u: bad iters %u/%u, words gpu-stale %" PRIu64 " cpu-stale %" PRIu64
             " other %" PRIu64 " → %s\n", t,
             fl & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT ? "DL " : "",
             fl & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT ? "HV " : "",
             coherent ? "HC " : "", fl & VK_MEMORY_PROPERTY_HOST_CACHED_BIT ? "CACHED" : "",
             mp.memoryTypes[t].heapIndex, bad_iters, iters, gpu_stale, cpu_stale, other,
             bad_iters ? "FAIL" : "PASS");
      printf("   stale age (iterations back):");
      for (int k = 1; k < 16; k++) if (age_hist[k]) printf(" %d%s:%" PRIu64, k, k == 15 ? "+" : "", age_hist[k]);
      printf("  unrecognised:%" PRIu64 "\n", junk);
      bad_total += bad_iters;
      free_buf(&src); free_buf(&dst);
   }
   vkDestroyFence(dev, fence, NULL);
   vkDestroyCommandPool(dev, pool, NULL);
   vkDestroyPipeline(dev, pipe, NULL);
   vkDestroyPipelineLayout(dev, pl, NULL);
   vkDestroyShaderModule(dev, sm, NULL);
   vkDestroyDevice(dev, NULL);
   vkDestroyInstance(inst, NULL);
   return bad_total ? 1 : 0;
}
