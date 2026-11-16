package com.scannerbridge.scanner_bridge;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;

import androidx.annotation.NonNull;

import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** Android DataWedge bridge for scanner_bridge. */
public class ScannerBridgePlugin extends BroadcastReceiver implements
        FlutterPlugin,
        MethodChannel.MethodCallHandler,
        EventChannel.StreamHandler {

    private static final String METHOD_CHANNEL = "scanner_bridge/zebra_barcode";
    private static final String EVENT_CHANNEL = "scanner_bridge/zebra_barcode/events";
    private static final String DATAWEDGE_PACKAGE = "com.symbol.datawedge";
    private static final String DATAWEDGE_ACTION = "com.symbol.datawedge.api.ACTION";
    private static final String SCAN_ACTION = "com.scannerbridge.scanner_bridge.SCAN";
    private static final String NOTIFICATION_ACTION = "com.symbol.datawedge.api.NOTIFICATION_ACTION";
    private static final String RESULT_ACTION = "com.symbol.datawedge.api.RESULT_ACTION";
    private static final String STATUS_NOTIFICATION = "SCANNER_STATUS";

    private Context applicationContext;
    private MethodChannel methodChannel;
    private EventChannel eventChannel;
    private EventChannel.EventSink eventSink;
    private boolean receiverRegistered;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        applicationContext = binding.getApplicationContext();
        methodChannel = new MethodChannel(binding.getBinaryMessenger(), METHOD_CHANNEL);
        eventChannel = new EventChannel(binding.getBinaryMessenger(), EVENT_CHANNEL);
        methodChannel.setMethodCallHandler(this);
        eventChannel.setStreamHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        stopDataWedge();
        if (methodChannel != null) {
            methodChannel.setMethodCallHandler(null);
        }
        if (eventChannel != null) {
            eventChannel.setStreamHandler(null);
        }
        methodChannel = null;
        eventChannel = null;
        applicationContext = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "isAvailable":
                result.success(isDataWedgeAvailable());
                break;
            case "start":
                if (!isDataWedgeAvailable()) {
                    result.error("zebra_unavailable", "Zebra DataWedge is not installed.", null);
                    return;
                }
                startDataWedge();
                result.success(null);
                break;
            case "stop":
                stopDataWedge();
                result.success(null);
                break;
            default:
                result.notImplemented();
        }
    }

    @Override
    public void onListen(Object arguments, EventChannel.EventSink events) {
        eventSink = events;
    }

    @Override
    public void onCancel(Object arguments) {
        eventSink = null;
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null || intent.getAction() == null) {
            return;
        }

        if (SCAN_ACTION.equals(intent.getAction())) {
            final String value = intent.getStringExtra("com.symbol.datawedge.data_string");
            final String format = intent.getStringExtra("com.symbol.datawedge.label_type");
            if (value == null || value.isEmpty()) {
                return;
            }
            final Map<String, Object> event = new HashMap<>();
            event.put("event", "barcode");
            event.put("value", value);
            event.put("format", format);
            sendEvent(event);
            return;
        }

        if (NOTIFICATION_ACTION.equals(intent.getAction()) &&
                intent.hasExtra("com.symbol.datawedge.api.NOTIFICATION")) {
            final Bundle notification = intent.getBundleExtra(
                    "com.symbol.datawedge.api.NOTIFICATION");
            if (notification == null ||
                    !STATUS_NOTIFICATION.equals(notification.getString("NOTIFICATION_TYPE"))) {
                return;
            }
            final Map<String, Object> event = new HashMap<>();
            event.put("event", "status");
            event.put("status", notification.getString("STATUS"));
            sendEvent(event);
        }
    }

    private boolean isDataWedgeAvailable() {
        if (applicationContext == null) {
            return false;
        }
        try {
            applicationContext.getPackageManager().getPackageInfo(DATAWEDGE_PACKAGE, 0);
            return true;
        } catch (PackageManager.NameNotFoundException ignored) {
            return false;
        }
    }

    private void startDataWedge() {
        if (!receiverRegistered) {
            registerReceiver();
        }
        registerScannerStatusNotification();
        sendDataWedgeIntentWithExtra("com.symbol.datawedge.api.GET_SCANNER_STATUS", "");
        configureProfile();
    }

    private void stopDataWedge() {
        if (applicationContext == null || !receiverRegistered) {
            return;
        }
        final Bundle notification = new Bundle();
        notification.putString("com.symbol.datawedge.api.APPLICATION_NAME",
                applicationContext.getPackageName());
        notification.putString("com.symbol.datawedge.api.NOTIFICATION_TYPE", STATUS_NOTIFICATION);
        final Intent intent = new Intent(DATAWEDGE_ACTION);
        intent.putExtra("com.symbol.datawedge.api.UNREGISTER_FOR_NOTIFICATION", notification);
        applicationContext.sendBroadcast(intent);

        applicationContext.unregisterReceiver(this);
        receiverRegistered = false;
    }

    private void registerReceiver() {
        final IntentFilter filter = new IntentFilter();
        filter.addAction(SCAN_ACTION);
        filter.addAction(NOTIFICATION_ACTION);
        filter.addAction(RESULT_ACTION);
        filter.addCategory(Intent.CATEGORY_DEFAULT);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            applicationContext.registerReceiver(this, filter, Context.RECEIVER_EXPORTED);
        } else {
            applicationContext.registerReceiver(this, filter);
        }
        receiverRegistered = true;
    }

    private void registerScannerStatusNotification() {
        final Bundle notification = new Bundle();
        notification.putString("com.symbol.datawedge.api.APPLICATION_NAME",
                applicationContext.getPackageName());
        notification.putString("com.symbol.datawedge.api.NOTIFICATION_TYPE", STATUS_NOTIFICATION);
        sendDataWedgeIntentWithExtra(
                "com.symbol.datawedge.api.REGISTER_FOR_NOTIFICATION", notification);
    }

    private void configureProfile() {
        final String profileName = applicationContext.getPackageName();
        final Bundle profile = new Bundle();
        profile.putString("PROFILE_NAME", profileName);
        profile.putString("PROFILE_ENABLED", "true");
        profile.putString("CONFIG_MODE", "CREATE_IF_NOT_EXIST");

        final Bundle app = new Bundle();
        app.putString("PACKAGE_NAME", applicationContext.getPackageName());
        app.putStringArray("ACTIVITY_LIST", new String[]{"*"});
        profile.putParcelableArray("APP_LIST", new Bundle[]{app});

        final Bundle barcode = new Bundle();
        barcode.putString("PLUGIN_NAME", "BARCODE");
        barcode.putString("RESET_CONFIG", "true");
        barcode.putBundle("PARAM_LIST", new Bundle());
        profile.putBundle("PLUGIN_CONFIG", barcode);
        sendDataWedgeIntentWithExtra("com.symbol.datawedge.api.SET_CONFIG", profile);

        final Bundle intentProfile = new Bundle();
        intentProfile.putString("PROFILE_NAME", profileName);
        intentProfile.putString("PROFILE_ENABLED", "true");
        intentProfile.putString("CONFIG_MODE", "UPDATE");
        final Bundle intentPlugin = new Bundle();
        intentPlugin.putString("PLUGIN_NAME", "INTENT");
        intentPlugin.putString("RESET_CONFIG", "true");
        final Bundle intentParams = new Bundle();
        intentParams.putString("intent_output_enabled", "true");
        intentParams.putString("intent_action", SCAN_ACTION);
        intentParams.putString("intent_delivery", "2");
        intentPlugin.putBundle("PARAM_LIST", intentParams);
        intentProfile.putBundle("PLUGIN_CONFIG", intentPlugin);
        sendDataWedgeIntentWithExtra("com.symbol.datawedge.api.SET_CONFIG", intentProfile);
    }

    private void sendDataWedgeIntentWithExtra(String key, Object value) {
        final Intent intent = new Intent(DATAWEDGE_ACTION);
        if (value instanceof Bundle) {
            intent.putExtra(key, (Bundle) value);
        } else {
            intent.putExtra(key, String.valueOf(value));
        }
        intent.putExtra("SEND_RESULT", "true");
        intent.putExtra("COMMAND_IDENTIFIER", "scanner_bridge");
        applicationContext.sendBroadcast(intent);
    }

    private void sendEvent(Map<String, Object> event) {
        if (eventSink != null) {
            eventSink.success(event);
        }
    }
}
