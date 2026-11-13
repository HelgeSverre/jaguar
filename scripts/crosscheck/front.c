// A minimal libretro frontend, for running an image in another emulator:
// load a core and a game, run N frames, optionally holding pad buttons for a
// range of frames, and save the last frame as a BMP and main memory as a
// .ram file next to it. Prints the picture size and the loudest sample.
//
//     front core.dylib game.jag frames out.bmp scratch-dir [id@from+len...]
//
// A button id is a RETRO_DEVICE_ID_JOYPAD_* number.
#include <dlfcn.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "libretro.h"

static enum retro_pixel_format format = RETRO_PIXEL_FORMAT_0RGB1555;
static unsigned char *picture; static unsigned pw, ph; static int loudest;
static int frame_now; static int hold_id[16], hold_from[16], hold_to[16], holds;
static const char *sysdir;

static void logger(enum retro_log_level level, const char *fmt, ...) {
   if (level < RETRO_LOG_WARN) return;
   va_list ap; va_start(ap, fmt); vfprintf(stderr, fmt, ap); va_end(ap);
}
static bool env(unsigned cmd, void *data) {
   switch (cmd) {
   case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: format = *(enum retro_pixel_format *)data; return true;
   case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
   case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY: *(const char **)data = sysdir; return true;
   case RETRO_ENVIRONMENT_GET_LOG_INTERFACE: ((struct retro_log_callback *)data)->log = logger; return true;
   case RETRO_ENVIRONMENT_GET_CAN_DUPE: *(bool *)data = true; return true;
   default: return false;
   }
}
static void video(const void *data, unsigned w, unsigned h, size_t pitch) {
   if (!data) return;
   if (w != pw || h != ph) { free(picture); picture = malloc(w * h * 3); pw = w; ph = h; }
   for (unsigned y = 0; y < h; y++) for (unsigned x = 0; x < w; x++) {
      unsigned char *o = picture + (y * w + x) * 3; unsigned r, g, b;
      if (format == RETRO_PIXEL_FORMAT_XRGB8888) {
         unsigned p = ((const unsigned *)((const char *)data + y * pitch))[x];
         r = p >> 16 & 255; g = p >> 8 & 255; b = p & 255;
      } else if (format == RETRO_PIXEL_FORMAT_RGB565) {
         unsigned p = ((const unsigned short *)((const char *)data + y * pitch))[x];
         r = (p >> 11) * 255 / 31; g = (p >> 5 & 63) * 255 / 63; b = (p & 31) * 255 / 31;
      } else {
         unsigned p = ((const unsigned short *)((const char *)data + y * pitch))[x];
         r = (p >> 10 & 31) * 255 / 31; g = (p >> 5 & 31) * 255 / 31; b = (p & 31) * 255 / 31;
      }
      o[0] = r; o[1] = g; o[2] = b;
   }
}
static void note(int s) { if (s < 0) s = -s; if (s > loudest) loudest = s; }
static void audio(int16_t l, int16_t r) { note(l); note(r); }
static size_t audio_batch(const int16_t *d, size_t n) { for (size_t i = 0; i < n * 2; i++) note(d[i]); return n; }
static void poll(void) {}
static int16_t input(unsigned port, unsigned device, unsigned index, unsigned id) {
   if (port != 0 || device != RETRO_DEVICE_JOYPAD) return 0;
   for (int i = 0; i < holds; i++)
      if (hold_id[i] == (int)id && frame_now >= hold_from[i] && frame_now < hold_to[i]) return 1;
   return 0;
}
#define SYM(name) name = dlsym(core, #name); if (!name) { fprintf(stderr, "no %s\n", #name); return 2; }
int main(int argc, char **argv) {
   if (argc < 6) { fprintf(stderr, "front core game frames out.bmp scratch-dir [id@from+len...]\n"); return 2; }
   void *core = dlopen(argv[1], RTLD_NOW);
   if (!core) { fprintf(stderr, "%s\n", dlerror()); return 2; }
   int frames = atoi(argv[3]); sysdir = argv[5];
   for (int i = 6; i < argc && holds < 16; i++, holds++) {
      int id, from, len; sscanf(argv[i], "%d@%d+%d", &id, &from, &len);
      hold_id[holds] = id; hold_from[holds] = from; hold_to[holds] = from + len;
   }
   void (*retro_set_environment)(retro_environment_t), (*retro_set_video_refresh)(retro_video_refresh_t);
   void (*retro_set_audio_sample)(retro_audio_sample_t), (*retro_set_audio_sample_batch)(retro_audio_sample_batch_t);
   void (*retro_set_input_poll)(retro_input_poll_t), (*retro_set_input_state)(retro_input_state_t);
   void (*retro_init)(void), (*retro_run)(void), (*retro_unload_game)(void), (*retro_deinit)(void);
   bool (*retro_load_game)(const struct retro_game_info *);
   SYM(retro_set_environment) SYM(retro_set_video_refresh) SYM(retro_set_audio_sample)
   SYM(retro_set_audio_sample_batch) SYM(retro_set_input_poll) SYM(retro_set_input_state)
   SYM(retro_init) SYM(retro_run) SYM(retro_load_game) SYM(retro_unload_game) SYM(retro_deinit)
   retro_set_environment(env); retro_set_video_refresh(video); retro_set_audio_sample(audio);
   retro_set_audio_sample_batch(audio_batch); retro_set_input_poll(poll); retro_set_input_state(input);
   retro_init();
   FILE *f = fopen(argv[2], "rb"); if (!f) { perror(argv[2]); return 2; }
   fseek(f, 0, SEEK_END); long size = ftell(f); rewind(f);
   void *bytes = malloc(size); fread(bytes, 1, size, f); fclose(f);
   struct retro_game_info game = { argv[2], bytes, size, NULL };
   if (!retro_load_game(&game)) { fprintf(stderr, "load failed\n"); return 1; }
   for (frame_now = 0; frame_now < frames; frame_now++) retro_run();
   if (picture) {
      // 24-bit BMP: rows bottom-up, blue first, padded to four bytes.
      unsigned row = (pw * 3 + 3) & ~3u, size = 54 + row * ph;
      unsigned char head[54] = { 'B', 'M' };
      unsigned fields[] = { size, 0, 54, 40, pw, ph, 1 | 24 << 16, 0, row * ph, 2835, 2835, 0, 0 };
      memcpy(head + 2, fields, sizeof fields);
      FILE *o = fopen(argv[4], "wb"); fwrite(head, 1, 54, o);
      unsigned char *line = calloc(row, 1);
      for (unsigned y = ph; y-- > 0;) {
         for (unsigned x = 0; x < pw; x++) {
            const unsigned char *p = picture + (y * pw + x) * 3;
            line[x * 3] = p[2]; line[x * 3 + 1] = p[1]; line[x * 3 + 2] = p[0];
         }
         fwrite(line, 1, row, o);
      }
      free(line); fclose(o);
   }
   {
      void *(*retro_get_memory_data)(unsigned) = dlsym(core, "retro_get_memory_data");
      size_t (*retro_get_memory_size)(unsigned) = dlsym(core, "retro_get_memory_size");
      char name[1024]; snprintf(name, sizeof name, "%s.ram", argv[4]);
      void *ram = retro_get_memory_data(RETRO_MEMORY_SYSTEM_RAM); size_t n = retro_get_memory_size(RETRO_MEMORY_SYSTEM_RAM);
      if (ram && n) { FILE *r = fopen(name, "wb"); fwrite(ram, 1, n, r); fclose(r); }
   }
   printf("%ux%u loudest %d\n", pw, ph, loudest);
   retro_unload_game(); retro_deinit();
   return 0;
}
