package com.excellentcalendar.contractspike;

import android.app.Instrumentation;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.os.Build;
import android.os.Bundle;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyInfo;
import android.security.keystore.KeyProperties;
import android.util.AtomicFile;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.*;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.util.*;
import javax.crypto.*;
import javax.crypto.spec.GCMParameterSpec;

/** Standalone synthetic APK, no INTERNET permission and no product dependency. */
public final class SyncStorageInstrumentation extends Instrumentation {
    private static final UUID ACCOUNT=UUID.fromString("11111111-1111-4111-8111-111111111111");
    private static final UUID WORKSPACE=UUID.fromString("44444444-4444-4444-8444-444444444444");
    private static final String ALIAS="ec.sync.spike.workspace."+WORKSPACE;
    private static final byte[] MAGIC="ECSKEY01".getBytes(StandardCharsets.US_ASCII);
    private static final String REVOKED=String.format(Locale.ROOT,"%064d",1);
    private Bundle arguments;
    private final ArrayList<String> passed=new ArrayList<>();
    private static native int nativeDatabase(String path,byte[] key,boolean create,String account,String workspace);
    @Override public void onCreate(Bundle args) { super.onCreate(args); arguments=args; start(); }
    private void check(String id,boolean valid) { if(!valid) throw new IllegalStateException(id); passed.add(id); }
    private static void guard(boolean valid) { if(!valid) throw new IllegalArgumentException("invalid key record"); }
    private interface Attempt { void run() throws Exception; }
    private void rejects(String id,Attempt attempt) throws Exception {
        boolean rejected=false; try { attempt.run(); } catch(GeneralSecurityException | IllegalArgumentException expected) { rejected=true; }
        check(id,rejected);
    }
    private File local(String name) { return new File(getTargetContext().getNoBackupFilesDir(),name); }
    private static byte[] read(File file) throws IOException {
        try(InputStream input=new FileInputStream(file);ByteArrayOutputStream output=new ByteArrayOutputStream()) {
            byte[] buffer=new byte[1024]; for(int n;(n=input.read(buffer))!=-1;) { guard(output.size()+n<=1024*1024); output.write(buffer,0,n); }
            return output.toByteArray();
        }
    }
    private static void atomic(File file,byte[] bytes) throws IOException {
        AtomicFile atomic=new AtomicFile(file); FileOutputStream output=null;
        try { output=atomic.startWrite(); output.write(bytes); atomic.finishWrite(output); }
        catch(IOException error) { if(output!=null) atomic.failWrite(output); throw error; }
    }
    private UUID installation() throws Exception {
        File file=local("installation.txt");
        if(file.exists()) { UUID id=UUID.fromString(new String(read(file),StandardCharsets.US_ASCII)); guard(id.version()==4); return id; }
        UUID id=UUID.randomUUID(); atomic(file,id.toString().getBytes(StandardCharsets.US_ASCII)); return id;
    }
    private static void uuid(ByteBuffer buffer,UUID id) { guard(id.version()==4 && id.variant()==2); buffer.putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()); }
    private static byte[] aad(UUID installation,UUID workspace,UUID account,int version,UUID wrapping) {
        ByteBuffer buffer=ByteBuffer.allocate(76); buffer.put(MAGIC); uuid(buffer,installation); uuid(buffer,workspace); uuid(buffer,account); buffer.putInt(version); uuid(buffer,wrapping); return buffer.array();
    }
    private static KeyStore store() throws Exception { KeyStore store=KeyStore.getInstance("AndroidKeyStore"); store.load(null); return store; }
    private static SecretKey wrappingKey() throws Exception {
        KeyGenerator generator=KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore");
        generator.init(new KeyGenParameterSpec.Builder(ALIAS,KeyProperties.PURPOSE_ENCRYPT|KeyProperties.PURPOSE_DECRYPT)
            .setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true).setUserAuthenticationRequired(false).build());
        return generator.generateKey();
    }
    private static byte[] wrap(byte[] key,UUID installation) throws Exception {
        guard(key.length==32); SecretKey wrapper=(SecretKey)store().getKey(ALIAS,null); guard(wrapper!=null);
        byte[] header=aad(installation,WORKSPACE,ACCOUNT,6,UUID.randomUUID()); Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE,wrapper); cipher.updateAAD(header); byte[] encrypted=cipher.doFinal(key);
        guard(cipher.getIV().length==12 && encrypted.length==48);
        return ByteBuffer.allocate(136).put(header).put(cipher.getIV()).put(encrypted).array();
    }
    private static byte[] unwrap(byte[] record,UUID installation,UUID workspace,UUID account,int version) throws Exception {
        guard(record.length==136);
        ByteBuffer id=ByteBuffer.wrap(record,60,16); UUID wrapping=new UUID(id.getLong(),id.getLong());
        byte[] header=aad(installation,workspace,account,version,wrapping);
        guard(Arrays.equals(header,Arrays.copyOf(record,76)));
        SecretKey wrapper=(SecretKey)store().getKey(ALIAS,null); guard(wrapper!=null);
        Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE,wrapper,new GCMParameterSpec(128,Arrays.copyOfRange(record,76,88)));
        cipher.updateAAD(header); byte[] key=cipher.doFinal(record,88,48); guard(key.length==32); return key;
    }
    private void verifyRevocations(UUID installation,boolean add) throws Exception {
        File path=local("proof-revocations.json"); TreeSet<String> keys=new TreeSet<>();
        if(path.exists()) {
            JSONObject old=new JSONObject(new String(read(path),StandardCharsets.UTF_8));
            guard(old.length()==3 && old.getInt("schema_version")==1 && old.getString("installation_id").equals(installation.toString()));
            JSONArray rows=old.getJSONArray("revoked_key_ids");
            for(int i=0;i<rows.length();++i) { String key=rows.getString(i); guard(key.matches("[0-9a-f]{64}") && keys.add(key)); }
        }
        if(add) keys.add(REVOKED);
        guard(keys.size()<=4096);
        JSONObject next=new JSONObject(); next.put("schema_version",1); next.put("installation_id",installation.toString()); next.put("revoked_key_ids",new JSONArray(keys));
        atomic(path,next.toString().getBytes(StandardCharsets.UTF_8));
        check(add?"revocation-record-initial":"revocation-survives-old-empty-trust",keys.contains(REVOKED));
    }
    private void initial(UUID installation) throws Exception {
        check("fresh-no-keystore-alias",!store().containsAlias(ALIAS)); SecretKey wrapper=wrappingKey();
        check("keystore-key-not-exportable",wrapper.getEncoded()==null);
        KeyInfo info=(KeyInfo)SecretKeyFactory.getInstance(wrapper.getAlgorithm(),"AndroidKeyStore").getKeySpec(wrapper,KeyInfo.class);
        check("keystore-aes256-gcm-background-policy",info.getKeySize()==256 && !info.isUserAuthenticationRequired() && Arrays.asList(info.getBlockModes()).contains("GCM"));
        byte[] key=new byte[32]; new SecureRandom().nextBytes(key); key[0]=0; // synthetic embedded-NUL JNI boundary case only.
        byte[] record=wrap(key,installation); byte[] second=wrap(key,installation);
        check("randomized-wrap-no-iv-reuse",!Arrays.equals(Arrays.copyOfRange(record,76,88),Arrays.copyOfRange(second,76,88)));
        check("wrapped-binary-layout-136",record.length==136);
        check("unwrap-exact-binary-key",Arrays.equals(key,unwrap(record,installation,WORKSPACE,ACCOUNT,6)));
        rejects("reject-account-aad",()->unwrap(record,installation,WORKSPACE,UUID.randomUUID(),6));
        rejects("reject-workspace-aad",()->unwrap(record,installation,UUID.randomUUID(),ACCOUNT,6));
        rejects("reject-installation-aad",()->unwrap(record,UUID.randomUUID(),WORKSPACE,ACCOUNT,6));
        rejects("reject-schema-aad",()->unwrap(record,installation,WORKSPACE,ACCOUNT,5));
        for(final int offset:new int[]{0,60,76,88,135}) {
            byte[] changed=record.clone(); changed[offset]^=1;
            rejects("reject-record-tamper-"+offset,()->unwrap(changed,installation,WORKSPACE,ACCOUNT,6));
        }
        rejects("reject-short-record",()->unwrap(Arrays.copyOf(record,135),installation,WORKSPACE,ACCOUNT,6));
        File db=new File(getTargetContext().getFilesDir(),"synthetic-account.sqlite3");
        check("jni-key-length-before-create",nativeDatabase(db.getAbsolutePath(),new byte[31],true,ACCOUNT.toString(),WORKSPACE.toString())==1 && !db.exists());
        check("keystore-jni-sqlcipher-20000-rows",nativeDatabase(db.getAbsolutePath(),key,true,ACCOUNT.toString(),WORKSPACE.toString())==0);
        byte[] wrong=key.clone(); wrong[31]^=1;
        check("sqlcipher-wrong-key-rejected",nativeDatabase(db.getAbsolutePath(),wrong,false,ACCOUNT.toString(),WORKSPACE.toString())!=0);
        check("sqlcipher-wrong-owner-rejected",nativeDatabase(db.getAbsolutePath(),key,false,UUID.randomUUID().toString(),WORKSPACE.toString())==16);
        check("sqlcipher-wrong-workspace-rejected",nativeDatabase(db.getAbsolutePath(),key,false,ACCOUNT.toString(),UUID.randomUUID().toString())==16);
        atomic(local("wrapped-key.bin"),record); Arrays.fill(key,(byte)0); Arrays.fill(wrong,(byte)0);
        verifyRevocations(installation,true);
    }
    private void reopen(UUID installation) throws Exception {
        byte[] key=unwrap(read(local("wrapped-key.bin")),installation,WORKSPACE,ACCOUNT,6);
        check("reopen-keystore-jni-encrypted-rows",nativeDatabase(new File(getTargetContext().getFilesDir(),"synthetic-account.sqlite3").getAbsolutePath(),key,false,ACCOUNT.toString(),WORKSPACE.toString())==0);
        Arrays.fill(key,(byte)0); verifyRevocations(installation,false);
    }
    private void destroy(UUID installation) throws Exception {
        store().deleteEntry(ALIAS); check("crypto-destroy-alias-absent",!store().containsAlias(ALIAS));
        check("ciphertext-files-may-remain",local("wrapped-key.bin").exists() && new File(getTargetContext().getFilesDir(),"synthetic-account.sqlite3").exists());
        byte[] record=read(local("wrapped-key.bin")); rejects("leftover-wrapper-cannot-recover-key",()->unwrap(record,installation,WORKSPACE,ACCOUNT,6));
    }
    @Override public void onStart() {
        Bundle output=new Bundle();
        try {
            System.loadLibrary("sync_keystore"); String phase=arguments.getString("phase"); UUID installation=installation();
            check("manifest-backup-disabled",(getTargetContext().getApplicationInfo().flags&ApplicationInfo.FLAG_ALLOW_BACKUP)==0);
            check("manifest-no-internet-permission",getTargetContext().checkSelfPermission("android.permission.INTERNET")!=android.content.pm.PackageManager.PERMISSION_GRANTED);
            if("initial".equals(phase)) initial(installation);
            else if("reopen".equals(phase) || "upgraded".equals(phase)) reopen(installation);
            else if("destroy".equals(phase)) destroy(installation);
            else if("reinstalled".equals(phase)) {
                check("reinstall-changes-installation",!installation.toString().equals(arguments.getString("previous_installation")));
                check("reinstall-has-no-old-keystore-key",!store().containsAlias(ALIAS));
                check("reinstall-has-no-old-account-or-wrapper",!local("wrapped-key.bin").exists() && !new File(getTargetContext().getFilesDir(),"synthetic-account.sqlite3").exists());
            } else if("restored-ciphertext".equals(phase)) {
                byte[] old=read(local("restored-wrapper.bin"));
                rejects("restored-wrapper-installation-rejected",()->unwrap(old,installation,WORKSPACE,ACCOUNT,6));
                ByteBuffer oldId=ByteBuffer.wrap(old,8,16); UUID oldInstallation=new UUID(oldId.getLong(),oldId.getLong());
                wrappingKey(); rejects("recreated-alias-cannot-decrypt-old-wrapper",()->unwrap(old,oldInstallation,WORKSPACE,ACCOUNT,6)); store().deleteEntry(ALIAS);
            } else throw new IllegalArgumentException("phase");
            output.putString("cases",new JSONArray(passed).toString()); output.putString("installation_id",installation.toString());
            output.putString("process_id",Integer.toString(android.os.Process.myPid())); output.putString("is_64_bit",Boolean.toString(android.os.Process.is64Bit()));
            output.putString("status","PASS"); finish(0,output);
        } catch(Throwable error) {
            // No exception messages, paths, key material or user data in results.
            output.putString("status","FAIL"); output.putString("error_type",error.getClass().getSimpleName()); output.putString("passed_cases",new JSONArray(passed).toString()); finish(1,output);
        }
    }
}
