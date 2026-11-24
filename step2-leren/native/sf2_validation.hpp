#pragma once

#include <array>
#include <cstdint>
#include <cstdio>
#include <cstring>

namespace keysight {

struct Sf2Chunk {
    uint32_t start = 0;
    uint32_t size = 0;
};

inline bool read_at(FILE *file, uint32_t offset, void *data, size_t size) {
    return std::fseek(file, offset, SEEK_SET) == 0 && std::fread(data, 1, size, file) == size;
}

inline uint16_t little16(const unsigned char *data) {
    return data[0] | uint16_t(data[1]) << 8;
}

inline uint32_t little32(const unsigned char *data) {
    return little16(data) | uint32_t(little16(data + 2)) << 16;
}

inline bool fourcc(const unsigned char *data, const char *id) {
    return std::memcmp(data, id, 4) == 0;
}

// Validate the RIFF boundaries and the terminal-index tables TinySoundFont
// follows during preset construction. PCM data itself is read by the synth.
inline bool validate_sf2(FILE *file, uint32_t &sample_count) {
    enum Table { PHDR, PBAG, PMOD, PGEN, INST, IBAG, IMOD, IGEN, SHDR };
    constexpr const char *ids[] = {"phdr", "pbag", "pmod", "pgen", "inst", "ibag", "imod", "igen", "shdr"};
    constexpr uint32_t widths[] = {38, 4, 10, 4, 22, 4, 10, 4, 46};
    std::array<Sf2Chunk, 9> tables{};
    std::array<unsigned char, 46> data;
    if (std::fseek(file, 0, SEEK_END) != 0) {
        return false;
    }
    const long size = std::ftell(file);
    if (size < 12 || uint64_t(size) > UINT32_MAX ||
            !read_at(file, 0, data.data(), 12) || !fourcc(data.data(), "RIFF") ||
            !fourcc(data.data() + 8, "sfbk") || little32(data.data() + 4) != size - 8) {
        return false;
    }

    bool pdta = false;
    bool sdta = false;
    for (uint32_t pos = 12; pos < size;) {
        if (size - pos < 12 || !read_at(file, pos, data.data(), 12) || !fourcc(data.data(), "LIST")) {
            return false;
        }
        const uint32_t list_size = little32(data.data() + 4);
        if (list_size < 4 || (list_size & 1) || list_size > size - pos - 8) {
            return false;
        }
        const bool presets = fourcc(data.data() + 8, "pdta");
        const bool samples = fourcc(data.data() + 8, "sdta");
        if ((presets && pdta) || (samples && sdta)) {
            return false;
        }
        pdta |= presets;
        sdta |= samples;
        const uint32_t end = pos + 8 + list_size;
        if (presets || samples) {
            for (uint32_t child = pos + 12; child < end;) {
                if (end - child < 8 || !read_at(file, child, data.data(), 8)) {
                    return false;
                }
                const uint32_t length = little32(data.data() + 4);
                // TinySoundFont advances by the unpadded size for these lists.
                if ((length & 1) || length > end - child - 8) {
                    return false;
                }
                if (presets) {
                    for (size_t i = 0; i < tables.size(); ++i) {
                        if (fourcc(data.data(), ids[i])) {
                            if (tables[i].start || length < widths[i] || length % widths[i]) {
                                return false;
                            }
                            tables[i] = {child + 8, length / widths[i]};
                            break;
                        }
                    }
                } else if (fourcc(data.data(), "smpl")) {
                    if (sample_count || length < 4) {
                        return false;
                    }
                    sample_count = length / 2;
                }
                child += 8 + length;
            }
        }
        pos = end;
    }

    if (!sample_count || tables[PHDR].size < 2 || tables[INST].size < 2 || tables[SHDR].size < 2) {
        return false;
    }
    for (const auto &table : tables) {
        if (!table.start) {
            return false;
        }
    }
    const auto check_indices = [&](Table from, uint32_t column, Table to) {
        uint16_t previous = 0;
        for (uint32_t i = 0; i < tables[from].size; ++i) {
            if (!read_at(file, tables[from].start + i * widths[from] + column, data.data(), 2)) {
                return false;
            }
            const uint16_t index = little16(data.data());
            if (index < previous || index >= tables[to].size) {
                return false;
            }
            previous = index;
        }
        return true;
    };
    if (!check_indices(PHDR, 24, PBAG) || !check_indices(PBAG, 0, PGEN) ||
            !check_indices(INST, 20, IBAG) || !check_indices(IBAG, 0, IGEN)) {
        return false;
    }
    for (Table table : {PGEN, IGEN}) {
        const unsigned tag = table == PGEN ? 41 : 53;
        const auto limit = tables[table == PGEN ? INST : SHDR].size - 1;
        for (uint32_t i = 0; i < tables[table].size; ++i) {
            if (!read_at(file, tables[table].start + i * widths[table], data.data(), 4) ||
                    (little16(data.data()) == tag && little16(data.data() + 2) >= limit)) {
                return false;
            }
        }
    }
    return true;
}

} // namespace keysight
