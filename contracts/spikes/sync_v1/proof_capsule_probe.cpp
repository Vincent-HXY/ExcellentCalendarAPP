// Isolated authenticated capsule consumer. Reuse the independently tested JCS
// and platform primitive without altering their sources or recorded evidence.
#define main isolated_jcs_entry
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wreturn-type"
#include "jcs_probe.cpp"
#pragma GCC diagnostic pop
#undef main
#if defined(_WIN32)
#define main isolated_signature_entry
#include "proof_signature_probe.cpp"
#undef main
#else
#include <jni.h>
#endif
#include <functional>
#include <fstream>
#include <sstream>

namespace proof {
using V = jcs::Value;
using Primitive = std::function<bool(const std::vector<std::uint8_t>&, const std::vector<std::uint8_t>&, const std::vector<std::uint8_t>&)>;
const V& field(const V& value, const std::string& key) {
    jcs::check(value.kind == V::Object);
    for (const auto& pair : value.object) if (pair.first == key) return pair.second;
    throw std::invalid_argument("missing field");
}
void keys(const V& value, std::initializer_list<const char*> expected) {
    jcs::check(value.kind == V::Object && value.object.size() == expected.size());
    for (const auto* name : expected) (void)field(value, name);
}
const std::string& str(const V& value) { jcs::check(value.kind == V::String); return value.string; }
bool equal(const V& value, const char* text) { return str(value) == text; }
void literal_number(const V& value, double number) { jcs::check(value.kind == V::Number && value.number == number); }
void hash_string(const std::string& text) { jcs::check(text.size() == 64 && text.find_first_not_of("0123456789abcdef") == std::string::npos); }
void account(const std::string& text) {
    jcs::check(text.size() == 36 && text[14] == '4' && std::string("89ab").find(text[19]) != std::string::npos);
    for (std::size_t i = 0; i < text.size(); ++i)
        jcs::check((i == 8 || i == 13 || i == 18 || i == 23) ? text[i] == '-' : std::string("0123456789abcdef").find(text[i]) != std::string::npos);
}
std::vector<std::uint8_t> hex_bytes(const std::string& text) {
    jcs::check(text.size() % 2 == 0 && text.find_first_not_of("0123456789abcdef") == std::string::npos);
    std::vector<std::uint8_t> out;
    for (std::size_t i = 0; i < text.size(); i += 2) out.push_back(static_cast<std::uint8_t>(std::stoul(text.substr(i, 2), nullptr, 16)));
    return out;
}
std::string b64(const std::string& raw) {
    const char* alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    std::string out; unsigned accumulator = 0, bits = 0;
    for (unsigned char byte : raw) { accumulator = (accumulator << 8) | byte; bits += 8;
        while (bits >= 6) { bits -= 6; out += alphabet[(accumulator >> bits) & 63]; }
    }
    if (bits) out += alphabet[(accumulator << (6 - bits)) & 63];
    return out;
}
std::string unb64(const std::string& text) {
    const std::string alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    jcs::check(!text.empty() && text.size() % 4 != 1);
    std::string out; unsigned accumulator = 0, bits = 0;
    for (char c : text) { const auto n = alphabet.find(c); jcs::check(n != std::string::npos);
        accumulator = (accumulator << 6) | static_cast<unsigned>(n); bits += 6;
        if (bits >= 8) { bits -= 8; out += static_cast<char>((accumulator >> bits) & 255); }
    }
    jcs::check(b64(out) == text); // padding and nonzero unused bits are forbidden.
    return out;
}
std::vector<std::uint8_t> bytes(const std::string& text) { return {text.begin(), text.end()}; }

// Authentication is deliberately separate from typed wire/domain validation.
// The caller must reconstruct claim_data from a validated wire value and bind
// its operation/range to durable local state before accepting any receipt.
bool authenticated(const std::string& input, const Primitive& primitive) {
    try {
        jcs::check(input.size() <= 4 * 1024 * 1024);
        const auto request = jcs::Parser(input).parse();
        keys(request, {"trust_store", "locally_revoked_keys", "token", "expected_account_id", "expected_purpose", "claim_data", "claimed_hash"});
        const auto& expectedAccount = str(field(request, "expected_account_id")); account(expectedAccount);
        const auto& purpose = str(field(request, "expected_purpose"));
        jcs::check(purpose == "device_fence" || purpose == "import_range_close" || purpose == "account_deleted");
        const auto& revoked = field(request, "locally_revoked_keys");
        jcs::check(revoked.kind == V::Array); std::set<std::string> revokedKeys;
        for (const auto& key : revoked.array) { hash_string(str(key)); jcs::check(revokedKeys.insert(str(key)).second); }
        const auto& token = str(field(request, "token")); jcs::check(token.size() <= 2048);
        const auto capsuleRaw = unb64(token); const auto capsule = jcs::Parser(capsuleRaw).parse();
        jcs::check(jcs::encode(capsule) == capsuleRaw); keys(capsule, {"claims", "signature"});
        const auto& claims = field(capsule, "claims");
        keys(claims, {"proof_version", "algorithm", "key_id", "account_id", "purpose", "claims_sha256"});
        literal_number(field(claims, "proof_version"), 1); jcs::check(equal(field(claims, "algorithm"), "rsa_pss_sha256"));
        jcs::check(str(field(claims, "account_id")) == expectedAccount && str(field(claims, "purpose")) == purpose);
        const auto& claimedHash = str(field(request, "claimed_hash")); hash_string(claimedHash);
        jcs::check(str(field(claims, "claims_sha256")) == claimedHash && sha256(jcs::encode(field(request, "claim_data"))) == claimedHash);
        const auto& keyId = str(field(claims, "key_id")); hash_string(keyId); jcs::check(!revokedKeys.count(keyId));
        const auto signature = unb64(str(field(capsule, "signature"))); jcs::check(signature.size() == 256);
        const auto& trust = field(request, "trust_store"); keys(trust, {"schema_version", "trust_store_id", "keys"});
        literal_number(field(trust, "schema_version"), 1);
        V addressed = trust; addressed.object.erase(std::remove_if(addressed.object.begin(), addressed.object.end(),
            [](const auto& pair) { return pair.first == "trust_store_id"; }), addressed.object.end());
        jcs::check(sha256(jcs::encode(addressed)) == str(field(trust, "trust_store_id")));
        const auto& entries = field(trust, "keys"); jcs::check(entries.kind == V::Array && !entries.array.empty() && entries.array.size() <= 32);
        std::string previous; std::vector<std::uint8_t> selected;
        for (const auto& entry : entries.array) {
            keys(entry, {"key_id", "algorithm", "exponent", "modulus_hex", "verification_status"});
            const auto& id = str(field(entry, "key_id")); hash_string(id); jcs::check(id > previous); previous = id;
            jcs::check(equal(field(entry, "algorithm"), "rsa_pss_sha256")); literal_number(field(entry, "exponent"), 65537);
            const auto modulus = hex_bytes(str(field(entry, "modulus_hex")));
            jcs::check(modulus.size() == 256 && (modulus[0] & 128));
            const std::string keyPrefix = "ExcellentCalendar.RSAKey.v1\n";
            jcs::check(sha256(keyPrefix + std::string("\x01\x00\x01", 3) + std::string(modulus.begin(), modulus.end())) == id);
            const auto& status = str(field(entry, "verification_status")); jcs::check(status == "trusted" || status == "revoked");
            if (id == keyId) { jcs::check(status == "trusted"); selected = modulus; }
        }
        jcs::check(!selected.empty());
        return primitive(selected, bytes("ExcellentCalendar.SyncProof.v1\n" + jcs::encode(claims)), bytes(signature));
    } catch (const std::exception&) { return false; }
}
}

#if defined(_WIN32)
int main(int argc, char** argv) {
    std::setlocale(LC_NUMERIC, "C"); std::fesetround(FE_TONEAREST);
    if (argc != 2 || std::string(argv[1]) != "--verify-lines") return 2;
    std::string line; while (std::getline(std::cin, line)) std::cout << (proof::authenticated(line, verify) ? "VALID" : "REJECT") << '\n';
    return 0;
}
#elif defined(__ANDROID__)
extern "C" JNIEXPORT jboolean JNICALL Java_ProofCapsuleAndroidProbe_nativeAuthenticate(JNIEnv* env, jclass owner, jbyteArray raw) {
    if (!raw || env->GetArrayLength(raw) > 4 * 1024 * 1024) return JNI_FALSE;
    const auto size = env->GetArrayLength(raw); std::string input(static_cast<std::size_t>(size), '\0');
    env->GetByteArrayRegion(raw, 0, size, reinterpret_cast<jbyte*>(&input[0]));
    if (env->ExceptionCheck()) { env->ExceptionClear(); return JNI_FALSE; }
    // Locale is established by the isolated harness before entering C++.
    std::setlocale(LC_NUMERIC, "C"); std::fesetround(FE_TONEAREST);
    return proof::authenticated(input, [=](const auto& modulus, const auto& message, const auto& signature) {
        const auto method = env->GetStaticMethodID(owner, "verifyPlatform", "([B[B[B)Z");
        if (!method || env->ExceptionCheck()) { env->ExceptionClear(); return false; }
        jbyteArray arrays[3]{}; const std::vector<std::uint8_t>* values[]{&modulus, &message, &signature};
        bool result = false;
        for (unsigned i = 0; i < 3; ++i) {
            arrays[i] = env->NewByteArray(static_cast<jsize>(values[i]->size()));
            if (!arrays[i] || env->ExceptionCheck()) break;
            env->SetByteArrayRegion(arrays[i], 0, static_cast<jsize>(values[i]->size()), reinterpret_cast<const jbyte*>(values[i]->data()));
            if (env->ExceptionCheck()) break;
        }
        if (!env->ExceptionCheck() && arrays[0] && arrays[1] && arrays[2]) result = env->CallStaticBooleanMethod(owner, method, arrays[0], arrays[1], arrays[2]) == JNI_TRUE;
        if (env->ExceptionCheck()) { env->ExceptionClear(); result = false; }
        for (auto array : arrays) if (array) env->DeleteLocalRef(array);
        return result;
    }) ? JNI_TRUE : JNI_FALSE;
}
#endif
