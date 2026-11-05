#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <libretro.h>
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstring>
#include <deque>
#include <map>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

extern "C" {
void retro_dqm_link_enable(bool);
void retro_dqm_appearance(const uint8_t *, const uint8_t *, bool);
void retro_dqm_link_attach(bool);
void retro_dqm_link_push(const uint8_t *, int);
int retro_dqm_link_poll(uint8_t *, int);
}

using namespace godot;
class DqmCore final : public RefCounted {
    GDCLASS(DqmCore, RefCounted)
    static DqmCore *instance;
    std::mutex core_mutex, output_mutex;
    std::atomic<bool> running{false};
    std::atomic<unsigned> buttons{0};
    std::thread worker;
    bool initialized = false, loaded = false;
    unsigned pixel_format = RETRO_PIXEL_FORMAT_0RGB1555;
    std::vector<uint8_t> frame = std::vector<uint8_t>(160 * 144 * 4, 0);
    std::deque<Vector2> audio;
    std::vector<retro_memory_descriptor> memory;
    std::map<std::string, std::string> options;
    double sample_rate = 32768.0, fps = 59.7275005696;

    static bool environment(unsigned command, void *data) {
        auto *s = instance;
        if (!s) return false;
        switch (command) {
            case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
                s->pixel_format = *static_cast<unsigned *>(data);
                return s->pixel_format == RETRO_PIXEL_FORMAT_RGB565 || s->pixel_format == RETRO_PIXEL_FORMAT_XRGB8888;
            case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION:
                *static_cast<unsigned *>(data) = 0; return true;
            case RETRO_ENVIRONMENT_SET_VARIABLES: {
                auto *vars = static_cast<retro_variable *>(data);
                for (; vars && vars->key; ++vars) {
                    std::string choices = vars->value ? vars->value : "";
                    auto start = choices.find("; ");
                    std::string value = start == std::string::npos ? "" : choices.substr(start + 2);
                    value = value.substr(0, value.find('|'));
                    s->options.emplace(vars->key, value);
                }
                s->options["gambatte_gb_link_mode"] = "Not Connected";
                s->options["gambatte_gb_colorization"] = "disabled";
                s->options["gambatte_gbc_color_correction"] = "disabled";
                s->options["gambatte_gb_bootloader"] = "disabled";
                return true;
            }
            case RETRO_ENVIRONMENT_GET_VARIABLE: {
                auto *var = static_cast<retro_variable *>(data);
                auto found = s->options.find(var->key);
                var->value = found == s->options.end() ? nullptr : found->second.c_str();
                return var->value != nullptr;
            }
            case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
                *static_cast<bool *>(data) = false; return true;
            case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
            case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
                *static_cast<const char **>(data) = nullptr; return true;
            case RETRO_ENVIRONMENT_SET_MEMORY_MAPS: {
                auto *maps = static_cast<retro_memory_map *>(data);
                s->memory.assign(maps->descriptors, maps->descriptors + maps->num_descriptors);
                return true;
            }
            case RETRO_ENVIRONMENT_GET_CAN_DUPE:
                *static_cast<bool *>(data) = true; return true;
            case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:
                return true;
            case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
            case RETRO_ENVIRONMENT_SET_SUPPORT_ACHIEVEMENTS:
            case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:
                return true;
            default: return false;
        }
    }
    static void video(const void *data, unsigned width, unsigned height, size_t pitch) {
        if (!instance || !data || width != 160 || height != 144) return;
        std::lock_guard<std::mutex> lock(instance->output_mutex);
        for (unsigned y = 0; y < height; ++y) {
            auto *row = static_cast<const uint8_t *>(data) + y * pitch;
            for (unsigned x = 0; x < width; ++x) {
                uint8_t r, g, b;
                if (instance->pixel_format == RETRO_PIXEL_FORMAT_RGB565) {
                    uint16_t p; std::memcpy(&p, row + x * 2, 2);
                    r = ((p >> 11) & 31) * 255 / 31;
                    g = ((p >> 5) & 63) * 255 / 63;
                    b = (p & 31) * 255 / 31;
                } else {
                    uint32_t p; std::memcpy(&p, row + x * 4, 4);
                    r = p >> 16; g = p >> 8; b = p;
                }
                size_t at = (y * width + x) * 4;
                instance->frame[at] = r; instance->frame[at + 1] = g;
                instance->frame[at + 2] = b; instance->frame[at + 3] = 255;
            }
        }
    }
    static size_t samples(const int16_t *data, size_t count) {
        if (!instance) return count;
        std::lock_guard<std::mutex> lock(instance->output_mutex);
        for (size_t i = 0; i < count; ++i) {
            if (instance->audio.size() >= 65536) instance->audio.pop_front();
            instance->audio.emplace_back(data[i * 2] / 32768.0, data[i * 2 + 1] / 32768.0);
        }
        return count;
    }
    static void sample(int16_t left, int16_t right) {
        int16_t pair[2] = {left, right}; samples(pair, 1);
    }
    static void input_poll() {}
    static int16_t input(unsigned port, unsigned device, unsigned, unsigned id) {
        if (!instance || port || device != RETRO_DEVICE_JOYPAD) return 0;
        unsigned mask = instance->buttons.load();
        return id == RETRO_DEVICE_ID_JOYPAD_MASK ? mask : (id < 16 && (mask & (1u << id)) ? 1 : 0);
    }
    void run_worker() {
        using clock = std::chrono::steady_clock;
        auto next = clock::now();
        auto interval = std::chrono::duration_cast<clock::duration>(std::chrono::duration<double>(1.0 / fps));
        while (running.load()) {
            { std::lock_guard<std::mutex> lock(core_mutex); retro_run(); }
            next += interval;
            if (clock::now() > next + interval * 4) next = clock::now();
            std::this_thread::sleep_until(next);
        }
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("load_rom", "data"), &DqmCore::load_rom);
        ClassDB::bind_method(D_METHOD("start"), &DqmCore::start);
        ClassDB::bind_method(D_METHOD("stop"), &DqmCore::stop);
        ClassDB::bind_method(D_METHOD("set_buttons", "mask"), &DqmCore::set_buttons);
        ClassDB::bind_method(D_METHOD("frame_rgba"), &DqmCore::frame_rgba);
        ClassDB::bind_method(D_METHOD("drain_audio", "maximum"), &DqmCore::drain_audio);
        ClassDB::bind_method(D_METHOD("get_sample_rate"), &DqmCore::get_sample_rate);
        ClassDB::bind_method(D_METHOD("battery_save"), &DqmCore::battery_save);
        ClassDB::bind_method(D_METHOD("load_battery", "data"), &DqmCore::load_battery);
        ClassDB::bind_method(D_METHOD("save_state"), &DqmCore::save_state);
        ClassDB::bind_method(D_METHOD("load_state", "data"), &DqmCore::load_state);
        ClassDB::bind_method(D_METHOD("read_bus", "address", "length"), &DqmCore::read_bus);
        ClassDB::bind_method(D_METHOD("advance_frames", "count", "mask"), &DqmCore::advance_frames);
        ClassDB::bind_method(D_METHOD("set_appearance", "tiles", "palette"), &DqmCore::set_appearance);
        ClassDB::bind_method(D_METHOD("set_link", "enabled"), &DqmCore::set_link);
        ClassDB::bind_method(D_METHOD("push_serial", "data"), &DqmCore::push_serial);
        ClassDB::bind_method(D_METHOD("poll_serial"), &DqmCore::poll_serial);
    }
public:
    DqmCore() {
        if (instance) return;
        instance = this;
        retro_set_environment(environment);
        retro_set_video_refresh(video);
        retro_set_audio_sample(sample);
        retro_set_audio_sample_batch(samples);
        retro_set_input_poll(input_poll);
        retro_set_input_state(input);
        retro_init(); initialized = true;
    }
    ~DqmCore() {
        if (!initialized) return;
        stop();
        if (loaded) retro_unload_game();
        retro_deinit(); instance = nullptr;
    }
    bool load_rom(PackedByteArray data) {
        if (!initialized || running || data.size() != 4194304) return false;
        if (loaded) retro_unload_game();
        retro_dqm_appearance(nullptr, nullptr, false);
        memory.clear();
        retro_game_info game = {nullptr, data.ptr(), static_cast<size_t>(data.size()), nullptr};
        loaded = retro_load_game(&game);
        if (loaded) {
            retro_system_av_info av{}; retro_get_system_av_info(&av);
            fps = av.timing.fps; sample_rate = av.timing.sample_rate;
        }
        return loaded;
    }
    void start() {
        if (!initialized || !loaded || running.exchange(true)) return;
        worker = std::thread(&DqmCore::run_worker, this);
    }
    void stop() {
        if (!initialized) return;
        retro_dqm_link_enable(false); // Wake a serial wait before joining the worker.
        running = false;
        if (worker.joinable()) worker.join();
        buttons = 0;
    }
    void set_buttons(int mask) { buttons = static_cast<unsigned>(mask) & 0xffff; }
    PackedByteArray frame_rgba() {
        PackedByteArray result;
        std::lock_guard<std::mutex> lock(output_mutex);
        result.resize(frame.size()); std::memcpy(result.ptrw(), frame.data(), frame.size()); return result;
    }
    PackedVector2Array drain_audio(int maximum) {
        PackedVector2Array result;
        std::lock_guard<std::mutex> lock(output_mutex);
        size_t count = std::min(audio.size(), static_cast<size_t>(std::clamp(maximum, 0, 65536)));
        result.resize(count);
        for (size_t i = 0; i < count; ++i) { result.set(i, audio.front()); audio.pop_front(); }
        return result;
    }
    double get_sample_rate() const { return sample_rate; }
    PackedByteArray battery_save() {
        PackedByteArray result;
        if (!loaded) return result;
        std::lock_guard<std::mutex> lock(core_mutex);
        size_t size = retro_get_memory_size(RETRO_MEMORY_SAVE_RAM);
        result.resize(size);
        if (size) std::memcpy(result.ptrw(), retro_get_memory_data(RETRO_MEMORY_SAVE_RAM), size);
        return result;
    }
    bool load_battery(PackedByteArray data) {
        if (!loaded) return false;
        std::lock_guard<std::mutex> lock(core_mutex);
        if (static_cast<size_t>(data.size()) != retro_get_memory_size(RETRO_MEMORY_SAVE_RAM)) return false;
        std::memcpy(retro_get_memory_data(RETRO_MEMORY_SAVE_RAM), data.ptr(), data.size()); return true;
    }
    PackedByteArray save_state() {
        PackedByteArray result;
        if (!loaded) return result;
        std::lock_guard<std::mutex> lock(core_mutex);
        result.resize(retro_serialize_size());
        if (!retro_serialize(result.ptrw(), result.size())) result.clear();
        return result;
    }
    bool load_state(PackedByteArray data) {
        if (!loaded || running) return false;
        std::lock_guard<std::mutex> lock(core_mutex);
        return retro_unserialize(data.ptr(), data.size());
    }
    PackedByteArray read_bus(int address, int length) {
        PackedByteArray result;
        if (!loaded || address < 0 || length < 0 || length > 65536 || address + length > 65536) return result;
        std::lock_guard<std::mutex> lock(core_mutex);
        result.resize(length); result.fill(0);
        for (int j = 0; j < length; ++j) {
            size_t a = address + j;
            for (const auto &d : memory) {
                if (d.ptr && a >= d.start && a - d.start < d.len) {
                    result.set(j, static_cast<uint8_t *>(d.ptr)[d.offset + a - d.start]); break;
                }
            }
        }
        return result;
    }
    void advance_frames(int count, int mask) {
        if (!loaded || running) return;
        buttons = mask;
        for (int i = 0; i < std::clamp(count, 0, 3600); ++i) retro_run();
        buttons = 0;
    }
    void set_appearance(PackedByteArray tiles, PackedByteArray palette) {
        if (!initialized) return;
        std::lock_guard<std::mutex> lock(core_mutex);
        bool valid = tiles.size() == 256 && palette.size() == 8;
        retro_dqm_appearance(valid ? tiles.ptr() : nullptr, valid ? palette.ptr() : nullptr, valid);
    }
    void set_link(bool enabled) {
        if (!initialized || !loaded) return;
        retro_dqm_link_enable(false);
        std::lock_guard<std::mutex> lock(core_mutex);
        retro_dqm_link_attach(enabled);
        retro_dqm_link_enable(enabled);
    }
    void push_serial(PackedByteArray data) {
        if (initialized && data.size() <= 2048 && data.size() % 2 == 0)
            retro_dqm_link_push(data.ptr(), data.size());
    }
    PackedByteArray poll_serial() {
        PackedByteArray result;
        if (!initialized) return result;
        result.resize(2048);
        result.resize(retro_dqm_link_poll(result.ptrw(), result.size())); return result;
    }
};
DqmCore *DqmCore::instance = nullptr;

static void initialize(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) ClassDB::register_class<DqmCore>();
}
static void terminate(ModuleInitializationLevel) {}
extern "C" GDExtensionBool GDE_EXPORT dqmcore_library_init(
    GDExtensionInterfaceGetProcAddress get_proc, GDExtensionClassLibraryPtr library,
    GDExtensionInitialization *initialization) {
    GDExtensionBinding::InitObject init(get_proc, library, initialization);
    init.register_initializer(initialize); init.register_terminator(terminate);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
