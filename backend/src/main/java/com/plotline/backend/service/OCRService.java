package com.plotline.backend.service;

import net.sourceforge.tess4j.ITessAPI;
import net.sourceforge.tess4j.Tesseract;
import net.sourceforge.tess4j.TesseractException;

import javax.imageio.ImageIO;
import java.awt.*;
import java.awt.image.BufferedImage;
import java.io.File;
import java.io.IOException;

public class OCRService {

    public static String extractTextFromImage(File imageFile) {
        Tesseract tesseract = new Tesseract();
        // Prefer env var from Dockerfile, fallback to common system paths
        String tessdata = System.getenv("TESSDATA_PREFIX");
        if (tessdata == null || tessdata.isBlank()) {
            // Ubuntu 22 package path
            tessdata = "/usr/share/tesseract-ocr/5/tessdata";
        }
        tesseract.setDatapath(tessdata);
        tesseract.setLanguage("eng");
        // Improve accuracy on receipts
        tesseract.setPageSegMode(ITessAPI.TessPageSegMode.PSM_AUTO);
        tesseract.setOcrEngineMode(ITessAPI.TessOcrEngineMode.OEM_LSTM_ONLY);
        tesseract.setVariable("user_defined_dpi", "300");
        tesseract.setVariable("preserve_interword_spaces", "1");
        tesseract.setVariable("tessedit_char_whitelist",
                "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.$:/- ");

        File scaled = null;
        try {
            BufferedImage original = ImageIO.read(imageFile);
            BufferedImage processed = preprocess(original);
            if (processed == null) return "";

            File processedFile = File.createTempFile("receipt-prepped-", ".png");
            ImageIO.write(processed, "png", processedFile);
            scaled = processedFile;

            String processedText = safeOcr(tesseract, processedFile);
            return processedText != null ? processedText : "";
        } catch (UnsatisfiedLinkError | IOException | OutOfMemoryError e) {
            // Fail gracefully if native libs are missing or image is too large
            e.printStackTrace();
            return "";
        } finally {
            if (scaled != null && scaled.exists()) {
                // best-effort cleanup
                scaled.delete();
            }
        }
    }

    // Basic receipt preprocessing: grayscale + light normalization/threshold
    private static BufferedImage preprocess(BufferedImage input) {
        if (input == null) return null;
        int maxDim = 1400; // reduce to avoid OOM
        BufferedImage gray = new BufferedImage(input.getWidth(), input.getHeight(), BufferedImage.TYPE_BYTE_GRAY);
        Graphics g = gray.getGraphics();
        g.drawImage(input, 0, 0, null);
        g.dispose();

        // Downscale if huge
        int w = gray.getWidth();
        int h = gray.getHeight();
        if (w > maxDim || h > maxDim) {
            double scale = Math.min((double) maxDim / w, (double) maxDim / h);
            int nw = (int) (w * scale);
            int nh = (int) (h * scale);
            Image tmp = gray.getScaledInstance(nw, nh, Image.SCALE_SMOOTH);
            BufferedImage resized = new BufferedImage(nw, nh, BufferedImage.TYPE_BYTE_GRAY);
            Graphics2D g2d = resized.createGraphics();
            g2d.drawImage(tmp, 0, 0, null);
            g2d.dispose();
            gray = resized;
        }

        // Simple contrast + threshold
        for (int y = 0; y < gray.getHeight(); y++) {
            for (int x = 0; x < gray.getWidth(); x++) {
                int rgb = gray.getRGB(x, y) & 0xFF;
                // boost contrast a bit
                int boosted = Math.min(255, (int) (rgb * 1.2));
                int bin = boosted > 180 ? 255 : (boosted < 80 ? 0 : boosted);
                int val = (bin << 16) | (bin << 8) | bin;
                gray.setRGB(x, y, (0xFF << 24) | val);
            }
        }
        return gray;
    }

    private static String safeOcr(Tesseract tess, File f) {
        try {
            return tess.doOCR(f);
        } catch (OutOfMemoryError e) {
            System.err.println("OCR OOM on file: " + f.getName());
            return "";
        } catch (Exception e) {
            return "";
        }
    }
}
