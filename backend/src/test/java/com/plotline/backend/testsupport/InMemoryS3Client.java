package com.plotline.backend.testsupport;

import software.amazon.awssdk.core.exception.SdkClientException;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.core.sync.ResponseTransformer;
import software.amazon.awssdk.http.AbortableInputStream;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.DeleteObjectResponse;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.HeadObjectRequest;
import software.amazon.awssdk.services.s3.model.HeadObjectResponse;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Request;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Response;
import software.amazon.awssdk.services.s3.model.NoSuchKeyException;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectResponse;
import software.amazon.awssdk.services.s3.model.S3Object;

import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * A minimal, in-memory implementation of the AWS {@link S3Client} interface for tests.
 *
 * <p>Only the operations that {@code GroceryListService} actually uses are implemented;
 * every other operation keeps the interface's default (which throws). Objects live in a
 * thread-safe map so concurrency tests behave like a shared store.
 *
 * <p>Reads route through the single {@code getObject(request, transformer)} core method,
 * which the SDK's {@code getObject(request)}, {@code getObjectAsBytes(request)} and
 * {@code getObject(Consumer)} overloads all delegate to.
 */
public class InMemoryS3Client implements S3Client {

    private final Map<String, byte[]> store = new ConcurrentHashMap<>();
    private final Map<String, Instant> lastModified = new ConcurrentHashMap<>();

    // ── Test hooks ─────────────────────────────────────────────────────────────

    /** Backdate an object's last-modified time (used to test archived auto-delete). */
    public void setLastModified(String key, Instant when) {
        if (store.containsKey(key)) {
            lastModified.put(key, when);
        }
    }

    public boolean contains(String key) {
        return store.containsKey(key);
    }

    public int objectCount() {
        return store.size();
    }

    /** Directly seed an object (used to set up edge-case state such as stale data). */
    public void putRaw(String key, byte[] data) {
        store.put(key, data);
        lastModified.put(key, Instant.now());
    }

    /** Directly remove an object without going through the service. */
    public void deleteRaw(String key) {
        store.remove(key);
        lastModified.remove(key);
    }

    // ── SdkClient / AutoCloseable ──────────────────────────────────────────────

    @Override
    public String serviceName() {
        return "s3-in-memory";
    }

    @Override
    public void close() {
        // no-op
    }

    // ── Operations used by GroceryListService ──────────────────────────────────

    @Override
    public PutObjectResponse putObject(PutObjectRequest request, RequestBody body) {
        try (InputStream in = body.contentStreamProvider().newStream()) {
            store.put(request.key(), in.readAllBytes());
            lastModified.put(request.key(), Instant.now());
            return PutObjectResponse.builder().build();
        } catch (Exception e) {
            throw SdkClientException.create("in-memory putObject failed", e);
        }
    }

    @Override
    public <ReturnT> ReturnT getObject(GetObjectRequest request,
            ResponseTransformer<GetObjectResponse, ReturnT> transformer) {
        byte[] data = store.get(request.key());
        if (data == null) {
            throw NoSuchKeyException.builder().message("No such key: " + request.key()).build();
        }
        try {
            GetObjectResponse response = GetObjectResponse.builder()
                    .contentLength((long) data.length)
                    .build();
            return transformer.transform(response, AbortableInputStream.create(new ByteArrayInputStream(data)));
        } catch (Exception e) {
            throw SdkClientException.create("in-memory getObject failed", e);
        }
    }

    @Override
    public DeleteObjectResponse deleteObject(DeleteObjectRequest request) {
        store.remove(request.key());
        lastModified.remove(request.key());
        return DeleteObjectResponse.builder().build();
    }

    @Override
    public ListObjectsV2Response listObjectsV2(ListObjectsV2Request request) {
        String prefix = request.prefix() == null ? "" : request.prefix();
        List<S3Object> contents = new ArrayList<>();
        for (Map.Entry<String, byte[]> entry : store.entrySet()) {
            if (entry.getKey().startsWith(prefix)) {
                contents.add(S3Object.builder()
                        .key(entry.getKey())
                        .size((long) entry.getValue().length)
                        .lastModified(lastModified.getOrDefault(entry.getKey(), Instant.now()))
                        .build());
            }
        }
        return ListObjectsV2Response.builder()
                .contents(contents)
                .keyCount(contents.size())
                .isTruncated(false)
                .build();
    }

    @Override
    public HeadObjectResponse headObject(HeadObjectRequest request) {
        byte[] data = store.get(request.key());
        if (data == null) {
            throw NoSuchKeyException.builder().message("No such key: " + request.key()).build();
        }
        return HeadObjectResponse.builder().contentLength((long) data.length).build();
    }
}
