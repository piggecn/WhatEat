package com.piggecn.whateat;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONObject;

/**
 * 首次使用配置页：手输服务器地址，或扫描网页「关于页 → 手机客户端配置」的二维码
 * （内容 {"base_url": "http://ip:端口"}，也兼容直接扫出纯 URL）。
 */
public class ConfigActivity extends Activity {

    private EditText urlInput;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(24), dp(56), dp(24), dp(24));
        root.setBackgroundColor(Color.rgb(255, 248, 240));

        TextView title = new TextView(this);
        title.setText("今天吃点啥");
        title.setTextSize(26);
        title.setTextColor(Color.rgb(255, 107, 53));
        title.setGravity(Gravity.CENTER);
        root.addView(title);

        TextView subtitle = new TextView(this);
        subtitle.setText("欢迎使用，请先配置服务器地址");
        subtitle.setTextSize(14);
        subtitle.setTextColor(Color.rgb(138, 128, 120));
        subtitle.setGravity(Gravity.CENTER);
        subtitle.setPadding(0, dp(8), 0, dp(32));
        root.addView(subtitle);

        TextView label = new TextView(this);
        label.setText("服务器地址");
        label.setTextSize(14);
        label.setTextColor(Color.rgb(61, 53, 48));
        label.setPadding(0, 0, 0, dp(6));
        root.addView(label);

        urlInput = new EditText(this);
        urlInput.setHint("http://192.168.1.10:8765 或 https://域名");
        urlInput.setTextSize(15);
        urlInput.setPadding(dp(12), dp(10), dp(12), dp(10));
        urlInput.setBackgroundColor(Color.WHITE);
        SharedPreferences sp = getSharedPreferences(MainActivity.PREFS, Context.MODE_PRIVATE);
        urlInput.setText(sp.getString(MainActivity.KEY_BASE_URL, ""));
        root.addView(urlInput);

        TextView hint = new TextView(this);
        hint.setText("地址在网页「关于 → 手机客户端配置」里，可扫码自动填入");
        hint.setTextSize(12);
        hint.setTextColor(Color.rgb(138, 128, 120));
        hint.setPadding(0, dp(6), 0, dp(16));
        root.addView(hint);

        Button scanBtn = new Button(this);
        scanBtn.setText("扫描二维码填地址");
        scanBtn.setAllCaps(false);
        scanBtn.setTextColor(Color.WHITE);
        scanBtn.setBackgroundColor(Color.rgb(255, 107, 53));
        LinearLayout.LayoutParams scanLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(48));
        scanLp.setMargins(0, 0, 0, dp(10));
        root.addView(scanBtn, scanLp);
        scanBtn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                if (checkSelfPermission(android.Manifest.permission.CAMERA)
                        != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                    requestPermissions(new String[]{android.Manifest.permission.CAMERA}, 3001);
                } else {
                    startActivityForResult(new Intent(ConfigActivity.this, ScanActivity.class), 3002);
                }
            }
        });

        Button saveBtn = new Button(this);
        saveBtn.setText("保存并打开");
        saveBtn.setAllCaps(false);
        saveBtn.setTextColor(Color.rgb(255, 107, 53));
        saveBtn.setBackgroundColor(Color.rgb(255, 240, 233));
        root.addView(saveBtn, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(48)));
        saveBtn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                String url = MainActivity.normalizeUrl(urlInput.getText().toString());
                if (url.isEmpty()) {
                    Toast.makeText(ConfigActivity.this, "请填写或扫描服务器地址",
                            Toast.LENGTH_SHORT).show();
                    return;
                }
                getSharedPreferences(MainActivity.PREFS, Context.MODE_PRIVATE)
                        .edit().putString(MainActivity.KEY_BASE_URL, url).apply();
                setResult(RESULT_OK);
                finish();
            }
        });

        setContentView(root);
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions,
                                           int[] grantResults) {
        if (requestCode == 3001) {
            if (grantResults.length > 0
                    && grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                startActivityForResult(new Intent(this, ScanActivity.class), 3002);
            } else {
                Toast.makeText(this, "没有相机权限，请手动填写地址", Toast.LENGTH_SHORT).show();
            }
        } else {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == 3002 && resultCode == RESULT_OK && data != null) {
            String text = data.getStringExtra("text");
            if (text != null && !text.trim().isEmpty()) {
                // 兼容 {"base_url": "..."} 与纯 URL 两种二维码内容
                String url = text.trim();
                try {
                    JSONObject json = new JSONObject(url);
                    String base = json.optString("base_url", "");
                    if (!base.isEmpty()) {
                        url = base;
                    }
                } catch (Exception ignored) {
                }
                urlInput.setText(MainActivity.normalizeUrl(url));
                Toast.makeText(this, "已识别地址：" + urlInput.getText(),
                        Toast.LENGTH_LONG).show();
            }
        } else {
            super.onActivityResult(requestCode, resultCode, data);
        }
    }

    private int dp(int v) {
        return Math.round(v * getResources().getDisplayMetrics().density);
    }
}
