package com.jleoz.sync.Database.json;

import android.content.Context;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import com.jleoz.sync.Database.DatabaseHandler;
import com.jleoz.sync.Items.Filter;
import com.jleoz.sync.Items.Task;
import com.jleoz.sync.Items.Trigger;

public class Exporter {

    public static String create(Context context) throws JSONException {

        DatabaseHandler dbHandler = new DatabaseHandler(context);
        JSONObject main = new JSONObject();

        JSONArray tasks = new JSONArray();
        for(Task task : dbHandler.getAllTasks()){
            tasks.put(task.asJSON());
        }
        main.put("tasks", tasks);

        JSONArray triggers = new JSONArray();
        for(Trigger trigger : dbHandler.getAllTrigger()){
            triggers.put(trigger.asJSON());
        }
        main.put("trigger", triggers);

        JSONArray filters = new JSONArray();
        for(Filter filter : dbHandler.getAllFilters()){
            filters.put(filter.asJSON());
        }
        main.put("filters", filters);


        return main.toString();
    }
}
