package com.jleoz.sync.Services;

import android.app.IntentService;
import android.content.Intent;
import androidx.annotation.Nullable;
import androidx.preference.PreferenceManager;
import com.jleoz.sync.Items.RemoteItem;
import com.jleoz.sync.R;
import com.jleoz.sync.Engine;
import com.jleoz.sync.util.FLog;

public class ThumbnailsLoadingService extends IntentService {

    private static final String TAG = "ThumbnailsLoadingSvc";
    public static final String REMOTE_ARG = "com.jleoz.sync.ThumbnailsLoadingService.REMOTE_ARG";
    public static final String HIDDEN_PATH = "com.jleoz.sync.ThumbnailsLoadingService.HIDDEN_PATH";
    public static final String SERVER_PORT = "com.jleoz.sync.ThumbnailsLoadingService.PORT";

    private Engine engine;
    private Process process;

    public ThumbnailsLoadingService() {
        super("com.jleoz.sync.ThumbnailLoadingService");
    }

    @Override
    public void onCreate() {
        super.onCreate();
        engine = new Engine(this);
    }

    @Override
    protected void onHandleIntent(@Nullable Intent intent) {
        if (intent == null) {
            return;
        }

        RemoteItem remote = intent.getParcelableExtra(REMOTE_ARG);
        String hiddenPath = "/" + intent.getStringExtra(HIDDEN_PATH) + '/' + remote.getName();
        int serverPort = intent.getIntExtra(SERVER_PORT, 29179);
        FLog.d(TAG, "onHandleIntent: hiddenPath=%s", hiddenPath);
        process = engine.serve(Engine.SERVE_PROTOCOL_HTTP, serverPort, false, null, null, remote, "", hiddenPath);
        if (process != null) {
            try {
                if(PreferenceManager.getDefaultSharedPreferences(this).
                        getBoolean(getString(R.string.pref_key_logs), false)) {
                    new Thread() {
                        @Override
                        public void run() {
                            engine.logErrorOutput(process);
                        }
                    }.start();
                }
                process.waitFor();
            } catch (InterruptedException e) {
                FLog.e(TAG, "onHandleIntent: error waiting for process", e);
            }
        }
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        if (process != null) {
            process.destroy();
        }
    }
}
