package com.tomi.tomi_app

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.graphics.Bitmap
import androidx.core.content.FileProvider
import com.google.zxing.BarcodeFormat
import com.google.zxing.MultiFormatWriter
import java.io.ByteArrayOutputStream
import java.io.File

object TomiLinks {
    @JvmStatic fun valid(value: String?): Boolean {
        if (value == null || value.length > 100) return false
        return Regex("^tomi://(profile|room)/[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$").matches(value) || Regex("^tomi://game/[a-fA-F0-9]{8}$").matches(value)
    }
    @JvmStatic fun png(value: String): ByteArray {
        require(valid(value))
        val matrix = MultiFormatWriter().encode(value, BarcodeFormat.QR_CODE, 512, 512)
        val bitmap = Bitmap.createBitmap(512,512,Bitmap.Config.ARGB_8888)
        val pixels = IntArray(512*512) { i -> if(matrix[i%512,i/512]) 0xff09202f.toInt() else 0xffffffff.toInt() }
        bitmap.setPixels(pixels,0,512,0,0,512,512)
        return ByteArrayOutputStream().use { out -> bitmap.compress(Bitmap.CompressFormat.PNG,100,out); bitmap.recycle(); out.toByteArray() }
    }
    @JvmStatic fun share(activity: Activity, value: String) {
        require(valid(value))
        val dir=File(activity.cacheDir,"qr").apply{mkdirs()}
        dir.listFiles()?.filter{System.currentTimeMillis()-it.lastModified()>86400000}?.forEach{it.delete()}
        val file=File(dir,"tomi-${java.util.UUID.randomUUID()}.png").apply{writeBytes(png(value))}
        val uri=FileProvider.getUriForFile(activity,activity.packageName+".tomi.files",file)
        val intent=Intent(Intent.ACTION_SEND).setType("image/png").putExtra(Intent.EXTRA_STREAM,uri).putExtra(Intent.EXTRA_TEXT,value).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        intent.clipData=ClipData.newRawUri("TOMI QR",uri)
        activity.startActivity(Intent.createChooser(intent,"مشاركة QR"))
    }
}
