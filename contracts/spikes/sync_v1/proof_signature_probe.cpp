// Platform RSA-PSS feasibility; no new cryptographic implementation/dependency.
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>
#include "sha256_probe.hpp"

#if defined(_WIN32)
#include <windows.h>
#include <bcrypt.h>

bool verify(const std::vector<std::uint8_t>& modulus, const std::vector<std::uint8_t>& message, const std::vector<std::uint8_t>& signature) {
    if (modulus.size() != 256 || !(modulus[0] & 0x80) || signature.size() != 256 || message.size() > 1048576) return false;
    BCRYPT_ALG_HANDLE algorithm = nullptr;
    if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_RSA_ALGORITHM, nullptr, 0) < 0) return false;
    struct CloseAlgorithm { BCRYPT_ALG_HANDLE value; ~CloseAlgorithm() { BCryptCloseAlgorithmProvider(value, 0); } } guard{algorithm};
    BCRYPT_RSAKEY_BLOB header{BCRYPT_RSAPUBLIC_MAGIC, 2048, 3, 256, 0, 0};
    std::vector<std::uint8_t> blob(sizeof(header) + 3 + modulus.size());
    std::memcpy(blob.data(), &header, sizeof(header));
    blob[sizeof(header)] = 1; blob[sizeof(header) + 1] = 0; blob[sizeof(header) + 2] = 1;
    std::memcpy(blob.data() + sizeof(header) + 3, modulus.data(), modulus.size());
    BCRYPT_KEY_HANDLE key = nullptr;
    if (BCryptImportKeyPair(algorithm, nullptr, BCRYPT_RSAPUBLIC_BLOB, &key, blob.data(), static_cast<ULONG>(blob.size()), 0) < 0) return false;
    struct DestroyKey { BCRYPT_KEY_HANDLE value; ~DestroyKey() { BCryptDestroyKey(value); } } keyGuard{key};
    sync_spike::Sha256 hash;
    hash.update(message.data(), message.size());
    auto digest = hash.finish();
    BCRYPT_PSS_PADDING_INFO padding{BCRYPT_SHA256_ALGORITHM, 32};
    return BCryptVerifySignature(key, &padding, digest.data(), static_cast<ULONG>(digest.size()),
        const_cast<PUCHAR>(signature.data()), static_cast<ULONG>(signature.size()), BCRYPT_PAD_PSS) >= 0;
}

std::vector<std::uint8_t> unhex(const std::string& value) {
    if (value.size() % 2) throw std::invalid_argument("hex");
    std::vector<std::uint8_t> result;
    for (std::size_t i = 0; i < value.size(); i += 2) {
        const auto pair = value.substr(i, 2);
        if (pair.find_first_not_of("0123456789abcdef") != std::string::npos) throw std::invalid_argument("hex");
        result.push_back(static_cast<std::uint8_t>(std::stoul(pair, nullptr, 16)));
    }
    return result;
}

int main(int argc, char** argv) {
    try {
        if (argc != 2) return 2;
        std::ifstream input(argv[1]);
        std::string line;
        unsigned count = 0;
        while (std::getline(input, line)) {
            std::istringstream row(line); std::vector<std::string> fields; std::string field;
            while (std::getline(row, field, '\t')) fields.push_back(field);
            if (fields.size() != 5) return 3;
            const bool actual = verify(unhex(fields[1]), unhex(fields[2]), unhex(fields[3]));
            if (actual != (fields[4] == "1")) { std::cerr << "FAIL " << fields[0] << '\n'; return 1; }
            ++count; std::cout << fields[0] << "\tPASS\n";
        }
        if (count != 14) return 4;
        std::cout << "PASS\t" << count << '\n';
        return 0;
    } catch (...) { return 5; }
}
#elif defined(__ANDROID__)
#include <jni.h>
extern "C" JNIEXPORT jboolean JNICALL Java_ProofSignatureProbe_nativeVerify(JNIEnv* env, jclass owner,
    jbyteArray modulus, jbyteArray message, jbyteArray signature) {
    if (!modulus || !message || !signature || env->GetArrayLength(modulus) != 256 || env->GetArrayLength(signature) != 256 || env->GetArrayLength(message) > 1048576) return JNI_FALSE;
    jbyte first = 0;
    env->GetByteArrayRegion(modulus, 0, 1, &first);
    if (env->ExceptionCheck()) { env->ExceptionClear(); return JNI_FALSE; }
    if (!(static_cast<unsigned char>(first) & 0x80)) return JNI_FALSE;
    // Only this fixed primitive is delegated; production C++ remains responsible
    // for pinned key selection and capsule/claims/account/range validation.
    const auto method = env->GetStaticMethodID(owner, "verifyPlatform", "([B[B[B)Z");
    if (!method || env->ExceptionCheck()) { env->ExceptionClear(); return JNI_FALSE; }
    const auto result = env->CallStaticBooleanMethod(owner, method, modulus, message, signature);
    if (env->ExceptionCheck()) { env->ExceptionClear(); return JNI_FALSE; }
    return result;
}
#endif
