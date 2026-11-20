package com.gscwd.fleet_scan;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

final class OperatorRosterStorage {
    private static final String ALIAS = "fleet_scanner_roster";
    private static final int IV_BYTES = 12;
    private final SharedPreferences preferences;

    OperatorRosterStorage(Context context) {
        preferences = context.getSharedPreferences("operator_roster", Context.MODE_PRIVATE);
    }

    void register(FlutterEngine engine) {
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),
                "com.gscwd.fleet_scan/roster").setMethodCallHandler((call, result) -> {
            String site = call.argument("site");
            if (site == null || site.isEmpty()) {
                result.error("invalid_site", "Missing ERPNext site.", null);
                return;
            }
            try {
                // Remove credentials kept by older versions of the scanner.
                if (preferences.contains(site)) preferences.edit().remove(site).apply();
                if ("read".equals(call.method)) {
                    result.success(read("operators:" + site));
                } else if ("write".equals(call.method)) {
                    String roster = call.argument("roster");
                    if (roster == null || roster.isEmpty()) {
                        result.error("invalid_roster", "Missing remembered operators.", null);
                        return;
                    }
                    write("operators:" + site, roster);
                    result.success(null);
                } else {
                    result.notImplemented();
                }
            } catch (Exception error) {
                result.error("roster_storage", "Could not access remembered operators.", null);
            }
        });
    }

    void registerSessionStorage(FlutterEngine engine) {
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),
                "com.gscwd.fleet_scan/session").setMethodCallHandler((call, result) -> {
            String site = call.argument("site");
            if (site == null || site.isEmpty()) {
                result.error("invalid_site", "Missing ERPNext site.", null);
                return;
            }
            String key = "session:" + site;
            try {
                switch (call.method) {
                    case "read":
                        result.success(read(key));
                        break;
                    case "write":
                        String session = call.argument("session");
                        if (session == null || session.isEmpty()) {
                            result.error("invalid_session", "Missing session.", null);
                            return;
                        }
                        write(key, session);
                        result.success(null);
                        break;
                    case "clear":
                        if (!preferences.edit().remove(key).commit()) {
                            throw new IllegalStateException("Could not remove the session.");
                        }
                        result.success(null);
                        break;
                    default:
                        result.notImplemented();
                }
            } catch (Exception error) {
                result.error("session_storage", "Could not access the saved session.", null);
            }
        });
    }

    private KeyStore keyStore() throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore");
        store.load(null);
        return store;
    }

    private String read(String site) throws Exception {
        String stored = preferences.getString(site, null);
        if (stored == null) return null;
        SecretKey key = (SecretKey) keyStore().getKey(ALIAS, null);
        if (key == null) return null;
        ByteBuffer buffer = ByteBuffer.wrap(Base64.decode(stored, Base64.NO_WRAP));
        byte[] iv = new byte[IV_BYTES];
        buffer.get(iv);
        byte[] ciphertext = new byte[buffer.remaining()];
        buffer.get(ciphertext);
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(128, iv));
        cipher.updateAAD(site.getBytes(StandardCharsets.UTF_8));
        return new String(cipher.doFinal(ciphertext), StandardCharsets.UTF_8);
    }

    private void write(String site, String roster) throws Exception {
        SecretKey key = (SecretKey) keyStore().getKey(ALIAS, null);
        if (key == null) {
            KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
            generator.init(new KeyGenParameterSpec.Builder(ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .build());
            key = generator.generateKey();
        }
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, key);
        cipher.updateAAD(site.getBytes(StandardCharsets.UTF_8));
        byte[] ciphertext = cipher.doFinal(roster.getBytes(StandardCharsets.UTF_8));
        byte[] encoded = ByteBuffer.allocate(cipher.getIV().length + ciphertext.length)
                .put(cipher.getIV()).put(ciphertext).array();
        if (!preferences.edit().putString(site, Base64.encodeToString(encoded, Base64.NO_WRAP)).commit()) {
            throw new IllegalStateException("Encrypted storage write failed.");
        }
    }
}
