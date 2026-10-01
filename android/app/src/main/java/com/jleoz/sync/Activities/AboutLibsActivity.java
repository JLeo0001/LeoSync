package com.jleoz.sync.Activities;

import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import androidx.appcompat.app.ActionBar;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import androidx.appcompat.widget.Toolbar;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import com.jleoz.sync.util.ActivityHelper;
import com.jleoz.sync.R;
import com.jleoz.sync.RecyclerViewAdapters.AboutLibrariesAdapter;

import static com.jleoz.sync.util.ActivityHelper.tryStartActivity;

public class AboutLibsActivity extends AppCompatActivity implements AboutLibrariesAdapter.OnClickListener {

    private List<String> libraryNames;
    private Map<String, String> libraryUrls;
    private Map<String, String> libraryLicences;
    private Map<String, String> libraryLicenceUrls;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        ActivityHelper.applyTheme(this);
        setContentView(R.layout.activity_about_libs);
        Toolbar toolbar = findViewById(R.id.toolbar);
        setSupportActionBar(toolbar);
        ActionBar actionBar = getSupportActionBar();
        if (actionBar != null) {
            actionBar.setDisplayHomeAsUpEnabled(true);
            actionBar.setDisplayShowHomeEnabled(true);
        }

        createData();
        RecyclerView recyclerView = findViewById(R.id.about_libs_list);
        recyclerView.setHasFixedSize(true);
        RecyclerView.LayoutManager layoutManager = new LinearLayoutManager(this);
        recyclerView.setLayoutManager(layoutManager);
        AboutLibrariesAdapter aboutLibrariesAdapter = new AboutLibrariesAdapter(libraryNames, libraryUrls, libraryLicences, libraryLicenceUrls, this);
        recyclerView.setAdapter(aboutLibrariesAdapter);
    }

    @Override
    public boolean onSupportNavigateUp() {
        onBackPressed();
        return true;
    }

    private void createData() {
        libraryNames = new ArrayList<>();
        libraryUrls = new HashMap<>();
        libraryLicences = new HashMap<>();
        libraryLicenceUrls = new HashMap<>();

        String androidSupportLibraries = "Android Support Libraries";
        libraryNames.add(androidSupportLibraries);
        libraryUrls.put(androidSupportLibraries, "https://developer.android.com/topic/libraries/support-library/");
        libraryLicences.put(androidSupportLibraries, "Licensed under Apache-2.0");
        libraryLicenceUrls.put(androidSupportLibraries, "http://www.apache.org/licenses/LICENSE-2.0");

        String floatingActionButtonSpeedDial = "Floating Action Button Speed Dial";
        libraryNames.add(floatingActionButtonSpeedDial);
        libraryUrls.put(floatingActionButtonSpeedDial, "https://github.com/leinardi/FloatingActionButtonSpeedDial");
        libraryLicences.put(floatingActionButtonSpeedDial, "Licensed under Apache-2.0");
        libraryLicenceUrls.put(floatingActionButtonSpeedDial, "https://github.com/leinardi/FloatingActionButtonSpeedDial/blob/master/LICENSE");

        String glide = "Glide";
        libraryNames.add(glide);
        libraryUrls.put(glide, "https://github.com/bumptech/glide");
        libraryLicences.put(glide, "BSD, part MIT and Apache 2.0");
        libraryLicenceUrls.put(glide, "https://github.com/bumptech/glide/blob/master/LICENSE");

        String markDownView = "MarkDown View";
        libraryNames.add(markDownView);
        libraryUrls.put(markDownView, "https://github.com/falnatsheh/MarkdownView");
        libraryLicences.put(markDownView, "Licensed under Apache-2.0");
        libraryLicenceUrls.put(markDownView, "https://github.com/falnatsheh/MarkdownView/blob/master/license.txt");

        String materialDesignIcons = "Material Design";
        libraryNames.add(materialDesignIcons);
        libraryUrls.put(materialDesignIcons, "https://github.com/Templarian/MaterialDesign");
        libraryLicences.put(materialDesignIcons, "Licensed under SIL Open Font 1.1");
        libraryLicenceUrls.put(materialDesignIcons, "http://scripts.sil.org/cms/scripts/page.php?item_id=OFL_web");

        String engine = "Engine";
        libraryNames.add(engine);
        libraryUrls.put(engine, "https://github.com/ncw/engine");
        libraryLicences.put(engine, "Licensed under MIT");
        libraryLicenceUrls.put(engine, "https://github.com/ncw/engine/blob/master/COPYING");

        String recyclerViewAnimators = "Recyclerview Animators";
        libraryNames.add(recyclerViewAnimators);
        libraryUrls.put(recyclerViewAnimators, "https://github.com/wasabeef/recyclerview-animators");
        libraryLicences.put(recyclerViewAnimators, "Licensed under Apache 2.0");
        libraryLicenceUrls.put(recyclerViewAnimators, "https://github.com/wasabeef/recyclerview-animators/blob/master/LICENSE");

        String toasty = "Toasty";
        libraryNames.add(toasty);
        libraryUrls.put(toasty, "https://github.com/GrenderG/Toasty");
        libraryLicences.put(toasty, "Licensed under LGPL-3.0");
        libraryLicenceUrls.put(toasty, "https://github.com/GrenderG/Toasty/blob/master/LICENSE");

        String engineExplorer = "engineExplorer";
        libraryNames.add(engineExplorer);
        libraryUrls.put(engineExplorer, "https://github.com/kaczmarkiewiczp/engineExplorer");
        libraryLicences.put(engineExplorer, "Licensed under MIT");
        libraryLicenceUrls.put(engineExplorer, "https://github.com/kaczmarkiewiczp/engineExplorer/blob/e5afbfda50c747bc088543dab9576d80bf99ec63/LICENSE");

        String okhttp = "OkHttp";
        libraryNames.add(okhttp);
        libraryUrls.put(okhttp, "https://square.github.io/okhttp");
        libraryLicences.put(okhttp, "Licensed under Apache 2.0");
        libraryLicenceUrls.put(okhttp, "https://square.github.io/okhttp/#license");

        String rfc3339 = "RFC 3339 Date Parser";
        libraryNames.add(rfc3339);
        libraryUrls.put(rfc3339, "https://github.com/x0b/rfc3339parser");
        libraryLicences.put(rfc3339, "Licensed under MIT");
        libraryLicenceUrls.put(rfc3339, "https://github.com/x0b/rfc3339parser/blob/master/LICENSE");


        String undraw = "unDraw - Open Source Illustrations";
        libraryNames.add(undraw);
        libraryUrls.put(undraw, "https://undraw.co/");
        libraryLicences.put(undraw, "Licensed under Custom License");
        libraryLicenceUrls.put(undraw, "https://undraw.co/license");
    }

    @Override
    public void onLibraryClick(String url) {
        Uri uri = Uri.parse(url);
        Intent intent = new Intent(Intent.ACTION_VIEW, uri);
        if (intent.resolveActivity(getPackageManager()) != null) {
            tryStartActivity(this, intent);
        }
    }
}
