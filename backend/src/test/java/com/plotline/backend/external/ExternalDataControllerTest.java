package com.plotline.backend.external;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/** News and food search go through the server, which holds the API keys and caches results. */
class ExternalDataControllerTest {

    /** records requested URLs; answers with a canned body or fails */
    static class FakeClient extends ExternalDataClient {
        final List<String> urls = new ArrayList<>();
        String body = "{}";
        boolean fail = false;

        @Override
        public String get(String url) throws IOException {
            urls.add(url);
            if (fail) throw new IOException("HTTP 500 from example");
            return body;
        }
    }

    private static final String NEWS = """
            {"status":"ok","articles":[
              {"title":"Stocks rally","description":"Markets up","url":"https://news.example/1","source":{"name":"X"},"author":"Y"},
              {"title":"[Removed]","description":null,"url":"https://removed.example"},
              {"title":"No link","url":""}
            ]}""";

    @Test
    @DisplayName("News: the server adds its key, picks the topic from the risk level, and returns only title/description/url")
    void newsThroughServer() {
        FakeClient client = new FakeClient();
        client.body = NEWS;
        ExternalDataController controller = new ExternalDataController(client, "news-key", null);

        var response = controller.news("High");

        assertThat(response.getStatusCode().value()).isEqualTo(200);
        assertThat(client.urls).hasSize(1);
        assertThat(client.urls.get(0)).startsWith("https://newsapi.org/v2/everything?q=growth+stocks+OR+speculative+tech")
                .contains("apiKey=news-key");
        assertThat(response.getBody())
                .isEqualTo("{\"articles\":[{\"title\":\"Stocks rally\",\"description\":\"Markets up\",\"url\":\"https://news.example/1\"}]}");
    }

    @Test
    @DisplayName("News is cached per topic, and unknown risk levels use the medium topic")
    void newsCached() {
        FakeClient client = new FakeClient();
        client.body = NEWS;
        ExternalDataController controller = new ExternalDataController(client, "news-key", null);

        controller.news("medium");
        controller.news("whatever");
        controller.news("MEDIUM");

        assertThat(client.urls).hasSize(1);
        assertThat(client.urls.get(0)).contains("q=stock+market+investing");
    }

    @Test
    @DisplayName("Without a news key the endpoint says so; provider failures return 502 and aren't cached")
    void newsFailures() {
        FakeClient client = new FakeClient();
        assertThat(new ExternalDataController(client, "", null).news("low").getStatusCode().value()).isEqualTo(503);
        assertThat(client.urls).isEmpty();

        client.fail = true;
        ExternalDataController controller = new ExternalDataController(client, "news-key", null);
        assertThat(controller.news("low").getStatusCode().value()).isEqualTo(502);
        client.fail = false;
        client.body = NEWS;
        assertThat(controller.news("low").getStatusCode().value()).isEqualTo(200);
        assertThat(client.urls).hasSize(2);
    }

    @Test
    @DisplayName("Food search: the server adds its key (USDA's demo key if none), passes USDA's answer through, and caches by query")
    void foodSearch() {
        FakeClient client = new FakeClient();
        client.body = "{\"foods\":[{\"description\":\"Banana, raw\",\"foodNutrients\":[]}]}";
        ExternalDataController controller = new ExternalDataController(client, null, null);

        var first = controller.foodSearch("  Banana ");
        var again = controller.foodSearch("banana");

        assertThat(first.getBody()).isEqualTo(client.body);
        assertThat(again.getBody()).isEqualTo(client.body);
        assertThat(client.urls).hasSize(1);
        assertThat(client.urls.get(0)).isEqualTo("https://api.nal.usda.gov/fdc/v1/foods/search?query=banana&pageSize=25&api_key=DEMO_KEY");

        assertThat(controller.foodSearch("   ").getBody()).isEqualTo("{\"foods\":[]}");
        assertThat(client.urls).hasSize(1);

        assertThat(new ExternalDataController(client, null, "usda-key").foodSearch("rice").getStatusCode().value()).isEqualTo(200);
        assertThat(client.urls.get(1)).endsWith("api_key=usda-key");
    }
}
