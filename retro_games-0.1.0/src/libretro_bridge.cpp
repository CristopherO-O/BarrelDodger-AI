#include <octave/oct.h>
#include <map>
#include <vector>
#include <string>
#include <cstring>
#include <stdint.h>

#if defined(_WIN32)
  #include <windows.h>
  #define DL_HANDLE HMODULE
  #define DL_OPEN(path) LoadLibraryA(path)
  #define DL_SYM(h, name) GetProcAddress(h, name)
  #define DL_CLOSE FreeLibrary
#else
  #include <dlfcn.h>
  #define DL_HANDLE void*
  #define DL_OPEN(path) dlopen(path, RTLD_LAZY)
  #define DL_SYM(h, name) dlsym(h, name)
  #define DL_CLOSE dlclose
#endif

typedef bool   (*retro_environment_t)(unsigned cmd, void *data);
typedef void   (*retro_video_refresh_t)(const void *data, unsigned width, unsigned height, size_t pitch);
typedef void   (*retro_audio_sample_t)(int16_t left, int16_t right);
typedef size_t (*retro_audio_sample_batch_t)(const int16_t *data, size_t frames);
typedef void   (*retro_input_poll_t)(void);
typedef int16_t(*retro_input_state_t)(unsigned port, unsigned device, unsigned index, unsigned id);

struct retro_game_info {
  const char *path;
  const void *data;
  size_t size;
  const char *meta;
};

struct retro_system_timing { double fps; double sample_rate; };

struct retro_game_geometry {
  unsigned base_width, base_height;
  unsigned max_width,  max_height;
  float aspect_ratio;
};

struct retro_system_av_info {
  retro_game_geometry geometry;
  retro_system_timing timing;
};

enum retro_pixel_format {
  RETRO_PIXEL_FORMAT_0RGB1555 = 0,
  RETRO_PIXEL_FORMAT_XRGB8888 = 1,
  RETRO_PIXEL_FORMAT_RGB565   = 2
};

enum {
  RETRO_ENVIRONMENT_SET_PIXEL_FORMAT   = 10,
  RETRO_ENVIRONMENT_GET_LOG_INTERFACE  = 27,
};

enum {
  RETRO_DEVICE_JOYPAD = 1,
  RETRO_DEVICE_ID_JOYPAD_B      = 0,
  RETRO_DEVICE_ID_JOYPAD_Y      = 1,
  RETRO_DEVICE_ID_JOYPAD_SELECT = 2,
  RETRO_DEVICE_ID_JOYPAD_START  = 3,
  RETRO_DEVICE_ID_JOYPAD_UP     = 4,
  RETRO_DEVICE_ID_JOYPAD_DOWN   = 5,
  RETRO_DEVICE_ID_JOYPAD_LEFT   = 6,
  RETRO_DEVICE_ID_JOYPAD_RIGHT  = 7,
  RETRO_DEVICE_ID_JOYPAD_A      = 8,
  RETRO_DEVICE_ID_JOYPAD_X      = 9,
  RETRO_DEVICE_ID_JOYPAD_L      = 10,
  RETRO_DEVICE_ID_JOYPAD_R      = 11
};

struct retro_log_callback { void (*log)(int level, const char *fmt, ...); };

static void dummy_log(int level, const char *fmt, ...) { (void)level; (void)fmt; }

typedef void   (*retro_init_t)(void);
typedef void   (*retro_deinit_t)(void);
typedef void   (*retro_get_system_av_info_t)(retro_system_av_info *info);
typedef void   (*retro_set_environment_t)(retro_environment_t);
typedef void   (*retro_set_video_refresh_t)(retro_video_refresh_t);
typedef void   (*retro_set_audio_sample_t)(retro_audio_sample_t);
typedef void   (*retro_set_audio_sample_batch_t)(retro_audio_sample_batch_t);
typedef void   (*retro_set_input_poll_t)(retro_input_poll_t);
typedef void   (*retro_set_input_state_t)(retro_input_state_t);
typedef void   (*retro_reset_t)(void);
typedef void   (*retro_run_t)(void);
typedef size_t (*retro_serialize_size_t)(void);
typedef bool   (*retro_serialize_t)(void *data, size_t size);
typedef bool   (*retro_unserialize_t)(const void *data, size_t size);
typedef bool   (*retro_load_game_t)(const retro_game_info *game);
typedef void   (*retro_unload_game_t)(void);

struct RetroInstance {
  DL_HANDLE handle;

  retro_init_t retro_init;
  retro_deinit_t retro_deinit;
  retro_get_system_av_info_t retro_get_system_av_info;
  retro_set_environment_t retro_set_environment;
  retro_set_video_refresh_t retro_set_video_refresh;
  retro_set_audio_sample_t retro_set_audio_sample;
  retro_set_audio_sample_batch_t retro_set_audio_sample_batch;
  retro_set_input_poll_t retro_set_input_poll;
  retro_set_input_state_t retro_set_input_state;
  retro_reset_t retro_reset;
  retro_run_t retro_run;
  retro_serialize_size_t retro_serialize_size;
  retro_serialize_t retro_serialize;
  retro_unserialize_t retro_unserialize;
  retro_load_game_t retro_load_game;
  retro_unload_game_t retro_unload_game;

  std::vector<uint8_t> frame;
  unsigned frame_w;
  unsigned frame_h;
  size_t   frame_pitch;
  retro_pixel_format pixfmt;

  int buttons[4][14];

  std::string core_path, rom_path, system_name;

  RetroInstance() :
    handle(nullptr),
    retro_init(nullptr), retro_deinit(nullptr), retro_get_system_av_info(nullptr),
    retro_set_environment(nullptr), retro_set_video_refresh(nullptr),
    retro_set_audio_sample(nullptr), retro_set_audio_sample_batch(nullptr),
    retro_set_input_poll(nullptr), retro_set_input_state(nullptr),
    retro_reset(nullptr), retro_run(nullptr),
    retro_serialize_size(nullptr), retro_serialize(nullptr),
    retro_unserialize(nullptr), retro_load_game(nullptr),
    retro_unload_game(nullptr),
    frame_w(0), frame_h(0), frame_pitch(0),
    pixfmt(RETRO_PIXEL_FORMAT_XRGB8888)
  {
    std::memset(buttons, 0, sizeof(buttons));
  }
};

static std::map<int, RetroInstance*> g_instances;
static int g_next_id = 1;
static RetroInstance* g_current = nullptr;

static bool env_cb(unsigned cmd, void *data);
static void video_cb(const void *data, unsigned width, unsigned height, size_t pitch);
static void audio_cb(int16_t, int16_t);
static size_t audio_batch_cb(const int16_t*, size_t);
static void input_poll_cb(void);
static int16_t input_state_cb(unsigned port, unsigned device, unsigned index, unsigned id);

template<typename T>
static void load_sym(DL_HANDLE h, T &fn, const char *name)
{
#if defined(_WIN32)
  FARPROC sym = DL_SYM(h, name);
  fn = reinterpret_cast<T>(sym);
#else
  void *sym = DL_SYM(h, name);
  fn = reinterpret_cast<T>(sym);
#endif
  if (!fn) {
    error("libretro_bridge: simbolo '%s' nao encontrado no core.", name);
  }
}

static void load_core_functions(RetroInstance *inst)
{
  load_sym(inst->handle, inst->retro_init,               "retro_init");
  load_sym(inst->handle, inst->retro_deinit,             "retro_deinit");
  load_sym(inst->handle, inst->retro_get_system_av_info, "retro_get_system_av_info");
  load_sym(inst->handle, inst->retro_set_environment,    "retro_set_environment");
  load_sym(inst->handle, inst->retro_set_video_refresh,  "retro_set_video_refresh");
  load_sym(inst->handle, inst->retro_set_audio_sample,   "retro_set_audio_sample");
  load_sym(inst->handle, inst->retro_set_audio_sample_batch, "retro_set_audio_sample_batch");
  load_sym(inst->handle, inst->retro_set_input_poll,     "retro_set_input_poll");
  load_sym(inst->handle, inst->retro_set_input_state,    "retro_set_input_state");
  load_sym(inst->handle, inst->retro_reset,              "retro_reset");
  load_sym(inst->handle, inst->retro_run,                "retro_run");
  load_sym(inst->handle, inst->retro_serialize_size,     "retro_serialize_size");
  load_sym(inst->handle, inst->retro_serialize,          "retro_serialize");
  load_sym(inst->handle, inst->retro_unserialize,        "retro_unserialize");
  load_sym(inst->handle, inst->retro_load_game,          "retro_load_game");
  load_sym(inst->handle, inst->retro_unload_game,        "retro_unload_game");
}

static bool env_cb(unsigned cmd, void *data)
{
  if (!g_current) return false;

  switch (cmd) {
    case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
    {
      retro_pixel_format *fmt = (retro_pixel_format*)data;
      g_current->pixfmt = *fmt;
      return true;
    }
    case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
    {
      retro_log_callback *cb = (retro_log_callback*)data;
      cb->log = dummy_log;
      return true;
    }
    default:
      return false;
  }
}

static void video_cb(const void *data, unsigned width, unsigned height, size_t pitch)
{
  if (!g_current) return;
  if (!data || width == 0 || height == 0) return;

  g_current->frame_w = width;
  g_current->frame_h = height;
  g_current->frame_pitch = pitch;

  const uint8_t *src = (const uint8_t*)data;
  size_t row_bytes = pitch;

  g_current->frame.resize(row_bytes * height);
  uint8_t *dst = g_current->frame.data();
  for (unsigned y = 0; y < height; ++y) {
    std::memcpy(dst + y * row_bytes, src + y * pitch, row_bytes);
  }
}

static void audio_cb(int16_t, int16_t) {}
static size_t audio_batch_cb(const int16_t*, size_t frames) { return frames; }
static void input_poll_cb(void) {}

static int16_t input_state_cb(unsigned port, unsigned device, unsigned index, unsigned id)
{
  if (!g_current) return 0;
  if (device != RETRO_DEVICE_JOYPAD || index != 0) return 0;
  if (port >= 4) return 0;

  int canonical = -1;
  switch (id) {
    case RETRO_DEVICE_ID_JOYPAD_START:  canonical = 0; break;
    case RETRO_DEVICE_ID_JOYPAD_SELECT: canonical = 1; break;
    case RETRO_DEVICE_ID_JOYPAD_UP:     canonical = 2; break;
    case RETRO_DEVICE_ID_JOYPAD_DOWN:   canonical = 3; break;
    case RETRO_DEVICE_ID_JOYPAD_LEFT:   canonical = 4; break;
    case RETRO_DEVICE_ID_JOYPAD_RIGHT:  canonical = 5; break;
    case RETRO_DEVICE_ID_JOYPAD_A:      canonical = 6; break;
    case RETRO_DEVICE_ID_JOYPAD_B:      canonical = 7; break;
    case RETRO_DEVICE_ID_JOYPAD_Y:      canonical = 8; break;
    case RETRO_DEVICE_ID_JOYPAD_X:      canonical = 9; break;
    case RETRO_DEVICE_ID_JOYPAD_L:      canonical = 12; break;
    case RETRO_DEVICE_ID_JOYPAD_R:      canonical = 13; break;
    default: canonical = -1;
  }

  if (canonical < 0 || canonical >= 14) return 0;
  return g_current->buttons[port][canonical] ? 1 : 0;
}

static RetroInstance* get_instance(int id)
{
  auto it = g_instances.find(id);
  if (it == g_instances.end()) error("libretro_bridge: id de jogo invalido.");
  return it->second;
}

static octave_value cmd_load_rom(const std::string &core_path,
                                 const std::string &rom_path,
                                 const std::string &system_name)
{
  RetroInstance *inst = new RetroInstance();
  inst->core_path = core_path;
  inst->rom_path = rom_path;
  inst->system_name = system_name;

  inst->handle = DL_OPEN(core_path.c_str());
  if (!inst->handle) {
#if defined(_WIN32)
    error("libretro_bridge: falha ao carregar core (LoadLibrary).");
#else
    error("libretro_bridge: falha ao carregar core (dlopen).");
#endif
  }

  load_core_functions(inst);

  g_current = inst;
  inst->retro_set_environment(env_cb);
  inst->retro_set_video_refresh(video_cb);
  inst->retro_set_audio_sample(audio_cb);
  inst->retro_set_audio_sample_batch(audio_batch_cb);
  inst->retro_set_input_poll(input_poll_cb);
  inst->retro_set_input_state(input_state_cb);

  inst->retro_init();

  retro_game_info info;
  std::memset(&info, 0, sizeof(info));
  info.path = rom_path.c_str();

  if (!inst->retro_load_game(&info)) {
    inst->retro_deinit();
    DL_CLOSE(inst->handle);
    delete inst;
    g_current = nullptr;
    error("libretro_bridge: retro_load_game falhou.");
  }

  int id = g_next_id++;
  g_instances[id] = inst;
  g_current = nullptr;

  return octave_value(id);
}

static void cmd_step(int id, uint64_t nframes)
{
  RetroInstance *inst = get_instance(id);
  g_current = inst;
  for (uint64_t i = 0; i < nframes; ++i) inst->retro_run();
  g_current = nullptr;
}

static void cmd_set_input(int id, uint64_t player, const Matrix &btns)
{
  RetroInstance *inst = get_instance(id);
  if (player < 1 || player > 4) error("libretro_bridge: player deve estar entre 1 e 4.");
  if (btns.numel() != 14) error("libretro_bridge: vetor de botoes deve ter 14 elementos.");

  int p = (int)player - 1;
  for (octave_idx_type i = 0; i < 14; ++i)
    inst->buttons[p][(int)i] = (btns(i) != 0.0) ? 1 : 0;
}

static octave_value cmd_get_image(int id)
{
  RetroInstance *inst = get_instance(id);

  if (inst->frame.empty() || inst->frame_w == 0 || inst->frame_h == 0) {
    uint8NDArray img(dim_vector(1,1,3));
    img(0,0,0)=0; img(0,0,1)=0; img(0,0,2)=0;
    return octave_value(img);
  }

  unsigned w = inst->frame_w;
  unsigned h = inst->frame_h;
  size_t pitch = inst->frame_pitch;
  const uint8_t *src = inst->frame.data();

  uint8NDArray img(dim_vector(h, w, 3));

  if (inst->pixfmt == RETRO_PIXEL_FORMAT_XRGB8888) {
    for (unsigned y = 0; y < h; ++y) {
      const uint32_t *row = (const uint32_t*)(src + y * pitch);
      for (unsigned x = 0; x < w; ++x) {
        uint32_t px = row[x];
        img(y,x,0) = (px >> 16) & 0xFF;
        img(y,x,1) = (px >>  8) & 0xFF;
        img(y,x,2) = (px      ) & 0xFF;
      }
    }
  } else if (inst->pixfmt == RETRO_PIXEL_FORMAT_RGB565) {
    for (unsigned y = 0; y < h; ++y) {
      const uint16_t *row = (const uint16_t*)(src + y * pitch);
      for (unsigned x = 0; x < w; ++x) {
        uint16_t px = row[x];
        img(y,x,0) = (uint8_t)(((px >> 11) & 0x1F) * 255 / 31);
        img(y,x,1) = (uint8_t)(((px >>  5) & 0x3F) * 255 / 63);
        img(y,x,2) = (uint8_t)(( px        & 0x1F) * 255 / 31);
      }
    }
  } else { // 0RGB1555 aproximado
    for (unsigned y = 0; y < h; ++y) {
      const uint16_t *row = (const uint16_t*)(src + y * pitch);
      for (unsigned x = 0; x < w; ++x) {
        uint16_t px = row[x];
        img(y,x,0) = (uint8_t)(((px >> 10) & 0x1F) * 255 / 31);
        img(y,x,1) = (uint8_t)(((px >>  5) & 0x1F) * 255 / 31);
        img(y,x,2) = (uint8_t)(( px        & 0x1F) * 255 / 31);
      }
    }
  }

  return octave_value(img);
}

static octave_value cmd_get_state(int id)
{
  RetroInstance *inst = get_instance(id);
  g_current = inst;

  size_t sz = inst->retro_serialize_size();
  if (sz == 0) { g_current=nullptr; error("libretro_bridge: serialize_size = 0."); }

  std::vector<uint8_t> buf(sz);
  if (!inst->retro_serialize(buf.data(), sz)) { g_current=nullptr; error("libretro_bridge: retro_serialize falhou."); }

  g_current = nullptr;

  uint8NDArray arr(dim_vector((octave_idx_type)sz, 1));
  for (size_t i = 0; i < sz; ++i) arr((octave_idx_type)i) = buf[i];
  return octave_value(arr);
}

static void cmd_set_state(int id, const uint8NDArray &arr)
{
  RetroInstance *inst = get_instance(id);
  size_t sz = (size_t)arr.numel();

  std::vector<uint8_t> buf(sz);
  for (size_t i = 0; i < sz; ++i)
    buf[i] = arr((octave_idx_type)i); // <-- corrigido (sem colchete errado)

  g_current = inst;
  if (!inst->retro_unserialize(buf.data(), sz)) { g_current=nullptr; error("libretro_bridge: retro_unserialize falhou."); }
  g_current = nullptr;
}

static void cmd_close(int id)
{
  auto it = g_instances.find(id);
  if (it == g_instances.end()) return;

  RetroInstance *inst = it->second;
  g_current = inst;

  if (inst->retro_unload_game) inst->retro_unload_game();
  if (inst->retro_deinit)      inst->retro_deinit();
  if (inst->handle)            DL_CLOSE(inst->handle);

  g_current = nullptr;
  delete inst;
  g_instances.erase(it);
}

DEFUN_DLD(libretro_bridge, args, ,
          "Internal Libretro bridge for retro_games package.")
{
  int nargin = args.length();
  if (nargin < 1 || !args(0).is_string())
    error("libretro_bridge: primeiro argumento deve ser comando string.");

  std::string cmd = args(0).string_value();

  if (cmd == "load_rom") {
    if (nargin < 4) error("libretro_bridge load_rom: core_path, rom_path, system_name");
    return octave_value_list(cmd_load_rom(args(1).string_value(),
                                          args(2).string_value(),
                                          args(3).string_value()));
  }
  else if (cmd == "step") {
    if (nargin < 3) error("libretro_bridge step: precisa de id e nframes.");
    cmd_step(args(1).int_value(), (uint64_t) args(2).double_value());
    return octave_value_list();
  }
  else if (cmd == "set_input") {
    if (nargin < 4) error("libretro_bridge set_input: precisa de id, player, vetor(14).");
    cmd_set_input(args(1).int_value(), (uint64_t) args(2).double_value(), args(3).matrix_value());
    return octave_value_list();
  }
  else if (cmd == "get_image") {
    if (nargin < 2) error("libretro_bridge get_image: precisa de id.");
    return octave_value_list(cmd_get_image(args(1).int_value()));
  }
  else if (cmd == "get_state") {
    if (nargin < 2) error("libretro_bridge get_state: precisa de id.");
    return octave_value_list(cmd_get_state(args(1).int_value()));
  }
  else if (cmd == "set_state") {
    if (nargin < 3) error("libretro_bridge set_state: precisa de id, state.");
    cmd_set_state(args(1).int_value(), args(2).uint8_array_value());
    return octave_value_list();
  }
  else if (cmd == "close") {
    if (nargin < 2) error("libretro_bridge close: precisa de id.");
    cmd_close(args(1).int_value());
    return octave_value_list();
  }

  error("libretro_bridge: comando desconhecido: %s", cmd.c_str());
  return octave_value_list();
}
