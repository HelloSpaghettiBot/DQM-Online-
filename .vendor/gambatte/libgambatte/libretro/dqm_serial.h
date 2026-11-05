// Authenticated transport lives in Godot; this bridge only carries cable bytes.
#pragma once
#include "gambatte.h"
#include <array>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <mutex>

class DqmSerial final : public gambatte::SerialIO {
    std::mutex mutex;
    std::condition_variable ready;
    std::deque<std::array<unsigned char, 2>> incoming, outgoing;
    bool enabled = false;
public:
    void enable(bool value) {
        std::lock_guard<std::mutex> lock(mutex);
        enabled = value;
        incoming.clear(); outgoing.clear(); ready.notify_all();
    }
    void push(unsigned char data, unsigned char mode) {
        std::lock_guard<std::mutex> lock(mutex);
        if (enabled && incoming.size() < 4096) incoming.push_back({data, mode});
        ready.notify_all();
    }
    int poll(unsigned char *data, int capacity) {
        std::lock_guard<std::mutex> lock(mutex);
        int count = 0;
        while (!outgoing.empty() && count + 2 <= capacity) {
            auto item = outgoing.front(); outgoing.pop_front();
            data[count++] = item[0]; data[count++] = item[1];
        }
        return count;
    }
    unsigned char send(unsigned char data, bool fast) override {
        std::unique_lock<std::mutex> lock(mutex);
        if (!enabled || outgoing.size() >= 4096) return 0xff;
        outgoing.push_back({data, static_cast<unsigned char>(fast)});
        bool received = ready.wait_for(lock, std::chrono::seconds(2), [&] {
            return !enabled || (!incoming.empty() && incoming.front()[1] == 128);
        });
        if (!received || !enabled) return 0xff;
        unsigned char answer = incoming.front()[0]; incoming.pop_front();
        return answer;
    }
    bool check(unsigned char out, unsigned char &in, bool &fast) override {
        std::lock_guard<std::mutex> lock(mutex);
        if (!enabled || incoming.empty() || incoming.front()[1] == 128 || outgoing.size() >= 4096)
            return false;
        auto item = incoming.front(); incoming.pop_front();
        in = item[0]; fast = item[1] != 0;
        outgoing.push_back({out, 128});
        return true;
    }
};
