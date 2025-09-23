package com.example.health_connect_calorie_app

import android.os.Bundle
import android.text.method.LinkMovementMethod
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.text.HtmlCompat

class PermissionsRationaleActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Create a layout to hold the views
        val layout = LinearLayout(this)
        layout.orientation = LinearLayout.VERTICAL
        layout.setPadding(48, 48, 48, 48)

        // Create a TextView for the rationale text
        val textView = TextView(this)
        val rationaleText = """
        <h2>Permission Rationale</h2>
        <p>This app integrates with Health Connect to read and display your calorie, step, and heart rate data.</p>
        <p>To do this, the app requires the following permissions:</p>
        <ul>
            <li><b>Activity Recognition:</b> To automatically track your physical activity.</li>
            <li><b>Location:</b> To calculate distance for activities like running and walking.</li>
            <li><b>Health Data:</b> To access specific metrics from Health Connect.</li>
        </ul>
        <p>Your data is kept on your device and is not shared. For more details, please see our <a href="https://example.com/privacy">Privacy Policy</a>.</p>
        """
        textView.text = HtmlCompat.fromHtml(rationaleText, HtmlCompat.FROM_HTML_MODE_LEGACY)
        textView.movementMethod = LinkMovementMethod.getInstance() // Make links clickable
        layout.addView(textView)

        // Create a button to close the activity
        val button = Button(this)
        button.text = "Got it"
        button.setOnClickListener {
            finish()
        }
        val params = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        )
        params.setMargins(0, 24, 0, 0)
        button.layoutParams = params
        layout.addView(button)

        setContentView(layout)
    }
}
