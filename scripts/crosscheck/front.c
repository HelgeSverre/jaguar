// A minimal libretro frontend, for running an image in another emulator:
// load a core and a game, run N frames, hold pad buttons, load and dump the
// EEPROM, save the framebuffer as BMP at chosen frames, and save main memory
// as a .ram file next to the final picture. Prints the picture size and the
// loudest sample.
//
//     front core game frames out.bmp scratch-dir [options] [id@from+len...]
//
//   --holds-file <file>   pad holds, whitespace separated: button@frame[+n]
//                         (n defaults to 6), the format of vjag_test --press;
//                         unlimited. Buttons: up down left right a b c option
//                         pause 0..6 (7 8 9 star hash need the keypad device
//                         and are rejected)
//   --hold <run>          one such run on the command line; repeatable
//   --eeprom-in <file>    128 bytes loaded into RETRO_MEMORY_SAVE_RAM after
//                         the game loads, before the first frame
//   --eeprom-out <file>   the first 128 bytes of RETRO_MEMORY_SAVE_RAM after
//                         the last frame
//   --shot <n>:<bmp>      save the picture after n frames have run; repeatable
//   --pal                 PAL console (core option virtualjaguar_pal)
//   --var key=value       any other core option, e.g. virtualjaguar_widescreen=disabled
//
// Frames are counted as in vjag_test: frame 0 is the first one run, a picture
// "after n frames" is what --frames n --screenshot saves. The old trailing
// arguments, bare libretro ids as id@from+len, still work.
#include <dlfcn.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include "libretro.h"

static enum retro_pixel_format format = RETRO_PIXEL_FORMAT_0RGB1555;
static unsigned char *picture; static unsigned pw, ph; static int loudest;
static int frame_now; static int *hold_id, *hold_from, *hold_to, holds, hold_cap;
static const char *vars[64][2]; static int nvars;
static struct { int frame; const char *path; } shots[256]; static int nshots;
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
   case RETRO_ENVIRONMENT_GET_VARIABLE: {
      struct retro_variable *v = data;
      for (int i = 0; i < nvars; i++) if (!strcmp(vars[i][0], v->key)) { v->value = vars[i][1]; return true; }
      return false;
   }
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
// 24-bit BMP: rows bottom-up, blue first, padded to four bytes.
static void bmp(const char *path) {
   if (!picture) return;
   unsigned row = (pw * 3 + 3) & ~3u, size = 54 + row * ph;
   unsigned char head[54] = { 'B', 'M' };
   unsigned fields[] = { size, 0, 54, 40, pw, ph, 1 | 24 << 16, 0, row * ph, 2835, 2835, 0, 0 };
   memcpy(head + 2, fields, sizeof fields);
   FILE *o = fopen(path, "wb"); if (!o) { perror(path); return; }
   fwrite(head, 1, 54, o);
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
static void note(int s) { if (s < 0) s = -s; if (s > loudest) loudest = s; }
static void audio(int16_t l, int16_t r) { note(l); note(r); }
static size_t audio_batch(const int16_t *d, size_t n) { for (size_t i = 0; i < n * 2; i++) note(d[i]); return n; }
static void poll(void) {}
static void add_hold(int id, int from, int len) {
   if (holds == hold_cap) {
      hold_cap = hold_cap ? hold_cap * 2 : 64;
      hold_id = realloc(hold_id, hold_cap * sizeof(int)); hold_from = realloc(hold_from, hold_cap * sizeof(int));
      hold_to = realloc(hold_to, hold_cap * sizeof(int));
   }
   hold_id[holds] = id; hold_from[holds] = from; hold_to[holds] = from + len; holds++;
}
static int button_id(const char *n) {
   static const struct { const char *name; int id; } t[] = {
      {"up", RETRO_DEVICE_ID_JOYPAD_UP}, {"down", RETRO_DEVICE_ID_JOYPAD_DOWN},
      {"left", RETRO_DEVICE_ID_JOYPAD_LEFT}, {"right", RETRO_DEVICE_ID_JOYPAD_RIGHT},
      {"a", RETRO_DEVICE_ID_JOYPAD_A}, {"b", RETRO_DEVICE_ID_JOYPAD_B}, {"c", RETRO_DEVICE_ID_JOYPAD_Y},
      {"pause", RETRO_DEVICE_ID_JOYPAD_SELECT}, {"option", RETRO_DEVICE_ID_JOYPAD_START},
      {"0", RETRO_DEVICE_ID_JOYPAD_X}, {"1", RETRO_DEVICE_ID_JOYPAD_L}, {"2", RETRO_DEVICE_ID_JOYPAD_R},
      {"3", RETRO_DEVICE_ID_JOYPAD_L2}, {"4", RETRO_DEVICE_ID_JOYPAD_R2},
      {"5", RETRO_DEVICE_ID_JOYPAD_L3}, {"6", RETRO_DEVICE_ID_JOYPAD_R3},
   };
   for (unsigned i = 0; i < sizeof t / sizeof *t; i++) if (!strcasecmp(t[i].name, n)) return t[i].id;
   return -1;
}
// One run, "button@frame[+n]". With raw set the button is a libretro id, as
// the old trailing arguments had it.
static int parse_hold(const char *w, int raw) {
   char name[32]; int from, len = 6;
   if (sscanf(w, "%31[^@]@%d+%d", name, &from, &len) < 2 || len < 1) { fprintf(stderr, "bad hold \"%s\"\n", w); return 0; }
   int id = raw ? atoi(name) : button_id(name);
   if (id < 0) { fprintf(stderr, "hold \"%s\": unknown button, or one the joypad cannot reach (7 8 9 star hash)\n", w); return 0; }
   add_hold(id, from, len); return 1;
}
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
   const char *eeprom_in = NULL, *eeprom_out = NULL, *bmp_name = argv[4];
   for (int i = 6; i < argc; i++) {
      const char *a = argv[i], *v = i + 1 < argc ? argv[i + 1] : NULL;
      if (!strcmp(a, "--holds-file") && v) {
         FILE *h = fopen(v, "r"); if (!h) { perror(v); return 2; }
         char w[128]; while (fscanf(h, "%127s", w) == 1) if (!parse_hold(w, 0)) return 2;
         fclose(h); i++;
      } else if (!strcmp(a, "--hold") && v) { if (!parse_hold(v, 0)) return 2; i++;
      } else if (!strcmp(a, "--eeprom-in") && v) { eeprom_in = v; i++;
      } else if (!strcmp(a, "--eeprom-out") && v) { eeprom_out = v; i++;
      } else if (!strcmp(a, "--pal")) { vars[nvars][0] = "virtualjaguar_pal"; vars[nvars++][1] = "enabled";
      } else if (!strcmp(a, "--var") && v && strchr(v, '=') && nvars < 64) {
         char *k = strdup(v), *e = strchr(k, '='); *e = 0; vars[nvars][0] = k; vars[nvars++][1] = e + 1; i++;
      } else if (!strcmp(a, "--shot") && v && strchr(v, ':') && nshots < 256) {
         shots[nshots].frame = atoi(v); shots[nshots++].path = strchr(v, ':') + 1; i++;
      } else if (a[0] != '-') { if (!parse_hold(a, 1)) return 2;
      } else { fprintf(stderr, "unknown option %s\n", a); return 2; }
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
   void *(*retro_get_memory_data)(unsigned) = dlsym(core, "retro_get_memory_data");
   size_t (*retro_get_memory_size)(unsigned) = dlsym(core, "retro_get_memory_size");
   if (eeprom_in) {
      unsigned char *save = retro_get_memory_data(RETRO_MEMORY_SAVE_RAM); size_t n = retro_get_memory_size(RETRO_MEMORY_SAVE_RAM);
      FILE *e = fopen(eeprom_in, "rb"); if (!e) { perror(eeprom_in); return 2; }
      unsigned char buf[129]; size_t got = fread(buf, 1, sizeof buf, e); fclose(e);
      if (got != 128) { fprintf(stderr, "%s: EEPROM image must be 128 bytes\n", eeprom_in); return 2; }
      if (!save || n < 128) { fprintf(stderr, "core exposes no save RAM for this image\n"); return 1; }
      memcpy(save, buf, 128);   // the core unpacks it into its EEPROM on the first retro_run
   }
   for (frame_now = 0; frame_now < frames; frame_now++) {
      for (int i = 0; i < nshots; i++) if (shots[i].frame == frame_now) bmp(shots[i].path);
      retro_run();
   }
   for (int i = 0; i < nshots; i++) if (shots[i].frame == frames) bmp(shots[i].path);
   bmp(bmp_name);
   if (eeprom_out) {
      unsigned char *save = retro_get_memory_data(RETRO_MEMORY_SAVE_RAM); size_t n = retro_get_memory_size(RETRO_MEMORY_SAVE_RAM);
      if (!save || n < 128) { fprintf(stderr, "core exposes no save RAM for this image\n"); return 1; }
      FILE *o = fopen(eeprom_out, "wb"); fwrite(save, 1, 128, o); fclose(o);
   }
   {
      char name[1024]; snprintf(name, sizeof name, "%s.ram", argv[4]);
      void *ram = retro_get_memory_data(RETRO_MEMORY_SYSTEM_RAM); size_t n = retro_get_memory_size(RETRO_MEMORY_SYSTEM_RAM);
      if (ram && n) { FILE *r = fopen(name, "wb"); fwrite(ram, 1, n, r); fclose(r); }
   }
   printf("%ux%u loudest %d\n", pw, ph, loudest);
   retro_unload_game(); retro_deinit();
   return 0;
}
