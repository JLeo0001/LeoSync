package com.jleoz.sync.RemoteConfig;

import android.content.Context;
import android.os.Environment;
import android.util.Log;
import android.widget.Toast;
import com.jleoz.sync.Items.RemoteItem;
import com.jleoz.sync.R;
import com.jleoz.sync.Engine;
import es.dmoral.toasty.Toasty;
import io.github.x0b.safdav.SafAccessProvider;
import io.github.x0b.safdav.file.SafConstants;

import java.util.ArrayList;

public class RemoteConfigHelper {

    public static String getRemotePath(String path, RemoteItem selectedRemote) {
        String remotePath;
        if (selectedRemote.isRemoteType(RemoteItem.LOCAL)) {
            if (path.equals("//" + selectedRemote.getName())) {
                remotePath = Environment.getExternalStorageDirectory().getAbsolutePath() + "/";
            } else {
                remotePath = Environment.getExternalStorageDirectory().getAbsolutePath() + "/" + path;
            }
        } else {
            if (path.equals("//" + selectedRemote.getName())) {
                remotePath = selectedRemote.getName() + ":";
            } else {
                remotePath = selectedRemote.getName() + ":" + path;
            }
        }
        return remotePath;
    }

    public static void updateAndWait(Context context, ArrayList<String> options) {
        Engine engine = new Engine(context);
        Process process = engine.configUpdate(options);
        engineRun(process, context, options);
    }

    public static void setupAndWait(Context context, ArrayList<String> options) {
        Engine engine = new Engine(context);
        Process process = engine.configCreate(options);
        engineRun(process, context, options);
    }

    private static void engineRun(Process process, Context context, ArrayList<String> options) {
        if (null == process) {
            Toasty.error(context, context.getString(R.string.error_creating_remote), Toast.LENGTH_SHORT, true).show();
            return;
        }
        int exitCode;
        while (true) {
            try {
                exitCode = process.waitFor();
                break;
            } catch (InterruptedException e) {
                try {
                    exitCode = process.exitValue();
                    break;
                } catch (IllegalStateException ignored) {}
            }
        }
        if (0 != exitCode) {
            Toasty.error(context, context.getString(R.string.error_creating_remote), Toast.LENGTH_SHORT, true).show();
        } else {
            Toasty.success(context, context.getString(R.string.remote_creation_success), Toast.LENGTH_SHORT, true).show();
        }
    }

    public static void enableSaf(Context context) {
        String user = SafAccessProvider.getUser(context);
        String pass = SafAccessProvider.getPassword(context);
        ArrayList<String> options = new ArrayList<>();
        options.add(SafConstants.SAF_REMOTE_NAME);
        options.add("webdav");
        options.add("url");
        options.add(SafConstants.SAF_REMOTE_URL);
        options.add("user");
        options.add(user);
        options.add("pass");
        options.add(pass);
        setupAndWait(context, options);
    }
}
