package com.plotline.backend.commute;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import com.fasterxml.jackson.databind.ObjectMapper;

class EiaPricesTest {

    @Test
    @DisplayName("A state's own weekly gas price where EIA has one, otherwise its region's")
    void series() {
        assertThat(EiaPrices.stateCode("Virginia")).isEqualTo("VA");
        assertThat(EiaPrices.stateCode("va")).isEqualTo("VA");
        assertThat(EiaPrices.stateCode("District of Columbia")).isEqualTo("DC");
        assertThat(EiaPrices.stateCode("Narnia")).isNull();
        assertThat(EiaPrices.gasSeries("VA")).isEqualTo("EMM_EPMR_PTE_R1Z_DPG");   // Lower Atlantic
        assertThat(EiaPrices.gasSeries("TX")).isEqualTo("EMM_EPMR_PTE_STX_DPG");   // Texas has its own
        assertThat(EiaPrices.gasSeries("CA")).isEqualTo("EMM_EPMR_PTE_SCA_DPG");
        assertThat(EiaPrices.gasSeries("NV")).isEqualTo("EMM_EPMR_PTE_R5XCA_DPG"); // West Coast without California
        assertThat(EiaPrices.gasSeries("DC")).isEqualTo("EMM_EPMR_PTE_R1Y_DPG");
        // every state has one
        for (String code : "AL AK AZ AR CA CO CT DE DC FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY".split(" ")) {
            assertThat(EiaPrices.gasSeries(code)).as(code).isNotNull();
        }
    }

    @Test
    @DisplayName("Reads the newest value, whether EIA sends it as a number or as text")
    void newest() throws Exception {
        ObjectMapper json = new ObjectMapper();
        assertThat(EiaPrices.newest(json.readTree("""
                {"response": {"data": [{"period": "2026-10-05", "value": 3.071}, {"period": "2026-09-28", "value": 3.1}]}}"""), "value"))
                .contains(3.071);
        assertThat(EiaPrices.newest(json.readTree("""
                {"response": {"data": [{"period": "2026-07", "price": "14.73"}]}}"""), "price")).contains(14.73);
        assertThat(EiaPrices.newest(json.readTree("""
                {"response": {"data": []}}"""), "value")).isEmpty();
    }
}
