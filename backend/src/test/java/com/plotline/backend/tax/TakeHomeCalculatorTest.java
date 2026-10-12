package com.plotline.backend.tax;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/** 2026 take-home pay, checked by hand against the published 2026 numbers. */
class TakeHomeCalculatorTest {

    private final TakeHomeCalculator calc;

    TakeHomeCalculatorTest() throws Exception {
        calc = new TakeHomeCalculator();
    }

    @Test
    @DisplayName("Federal: $60,000 in Texas (no state tax), standard deduction taken off first")
    void federalOnly() {
        var r = calc.calculate(60_000, "TX", 0, 0);
        // taxable 60,000 - 16,100 = 43,900: 10% of 12,400 + 12% of 31,500 = 1,240 + 3,780
        assertThat(r.federalTax()).isCloseTo(5_020, within(0.01));
        assertThat(r.socialSecurity()).isCloseTo(3_720, within(0.01));
        assertThat(r.medicare()).isCloseTo(870, within(0.01));
        assertThat(r.stateTax()).isZero();
        assertThat(r.takeHome()).isCloseTo(60_000 - 5_020 - 3_720 - 870, within(0.01));
    }

    @Test
    @DisplayName("401(k) and health premiums lower income tax; only health premiums lower Social Security/Medicare")
    void preTax() {
        var r = calc.calculate(60_000, "TX", 5, 2_400);
        assertThat(r.k401()).isEqualTo(3_000);
        // taxable 60,000 - 3,000 - 2,400 - 16,100 = 38,500: 1,240 + 12% of 26,100
        assertThat(r.federalTax()).isCloseTo(4_372, within(0.01));
        assertThat(r.socialSecurity()).isCloseTo(57_600 * 0.062, within(0.01));
    }

    @Test
    @DisplayName("Virginia 2026: brackets after its $8,750 deduction and $930 exemption")
    void virginia() {
        var r = calc.calculate(60_000, "VA", 0, 0);
        double taxable = 60_000 - 8_750 - 930; // 50,320
        double expected = 3_000 * .02 + 2_000 * .03 + 12_000 * .05 + (taxable - 17_000) * .0575;
        assertThat(r.stateTax()).isCloseTo(expected, within(0.01));
        assertThat(r.stateName()).isEqualTo("Virginia");
    }

    @Test
    @DisplayName("Mid-2026 changes are in: Georgia 4.99%, Utah 4.45%, South Carolina 1.99%/5.21%")
    void midYearChanges() {
        assertThat(calc.calculate(50_000, "GA", 0, 0).stateTax()).isCloseTo((50_000 - 12_000) * .0499, within(0.01));
        // Utah: 4.45% minus the taxpayer credit, which shrinks 1.3% of income over $18,213
        double utCredit = Math.max(0, 966 - (50_000 - 18_213) * .013);
        assertThat(calc.calculate(50_000, "UT", 0, 0).stateTax()).isCloseTo(50_000 * .0445 - utCredit, within(0.01));
        double scTaxable = 50_000 - 15_000;
        assertThat(calc.calculate(50_000, "SC", 0, 0).stateTax())
                .isCloseTo(30_000 * .0199 + (scTaxable - 30_000) * .0521, within(0.01));
    }

    @Test
    @DisplayName("Social Security stops at the $184,500 wage base; extra Medicare over $200,000; 401(k) capped at $24,500")
    void caps() {
        var r = calc.calculate(250_000, "FL", 20, 0);
        assertThat(r.socialSecurity()).isCloseTo(184_500 * .062, within(0.01));
        assertThat(r.medicare()).isCloseTo(250_000 * .0145 + 50_000 * .009, within(0.01));
        assertThat(r.k401()).isEqualTo(24_500);
    }

    @Test
    @DisplayName("Pennsylvania taxes 401(k) money; locations resolve to a state")
    void pennsylvaniaAndLocations() {
        var r = calc.calculate(50_000, "PA", 10, 0);
        assertThat(r.stateTax()).isCloseTo(50_000 * .0307, within(0.01));
        assertThat(calc.stateCode("Pittsburgh, Pennsylvania")).isEqualTo("PA");
        assertThat(calc.stateCode("Richmond, VA")).isEqualTo("VA");
        assertThat(calc.stateCode("Paris, France")).isNull();
    }

    @Test
    @DisplayName("Every state and DC is in the table, with brackets in order")
    void allStates() {
        assertThat(calc.states().size()).isEqualTo(51);
        calc.states().fields().forEachRemaining(e -> {
            double last = -1;
            for (var b : e.getValue().path("brackets")) {
                assertThat(b.path("over").asDouble()).as(e.getKey()).isGreaterThan(last);
                assertThat(b.path("rate").asDouble()).as(e.getKey()).isBetween(0.0, 0.15);
                last = b.path("over").asDouble();
            }
        });
    }
}
