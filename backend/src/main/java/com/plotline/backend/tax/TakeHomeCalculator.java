package com.plotline.backend.tax;

import java.io.InputStream;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;

import org.springframework.stereotype.Component;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Take-home pay from a salary, with 2026 rules for a single filer (resources/tax/tax_2026.json):
 * federal income tax after the standard deduction, Social Security and Medicare, and the state's
 * income tax after its own deductions, exemptions and credits. City/county taxes and most
 * income-based phase-outs aren't included, so it's an estimate.
 *
 * The budget quiz and the paycheck calculator both use this, so they always agree. (The quiz used
 * 2024 tables and taxed income without the standard deduction, which made take-home look smaller.)
 */
@Component
public class TakeHomeCalculator {

    /** a year of pay, all amounts per year */
    public record Result(double gross, double k401, double preTaxHealth, double federalTax, double socialSecurity,
                         double medicare, double stateTax, double takeHome, String state, String stateName,
                         String stateNote, int year) {
        public Map<String, Object> toMap(int payPeriods) {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("year", year);
            m.put("state", state);
            m.put("stateName", stateName);
            if (stateNote != null) m.put("stateNote", stateNote);
            m.put("payPeriods", payPeriods);
            m.put("yearly", amounts(1));
            m.put("perPaycheck", amounts(payPeriods));
            return m;
        }

        private Map<String, Object> amounts(int divideBy) {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("gross", round(gross / divideBy));
            m.put("k401", round(k401 / divideBy));
            m.put("preTaxHealth", round(preTaxHealth / divideBy));
            m.put("federalTax", round(federalTax / divideBy));
            m.put("socialSecurity", round(socialSecurity / divideBy));
            m.put("medicare", round(medicare / divideBy));
            m.put("stateTax", round(stateTax / divideBy));
            m.put("takeHome", round(takeHome / divideBy));
            return m;
        }
    }

    private final JsonNode table;

    public TakeHomeCalculator() throws Exception {
        try (InputStream in = getClass().getClassLoader().getResourceAsStream("tax/tax_2026.json")) {
            this.table = new ObjectMapper().readTree(in);
        }
    }

    public int year() { return table.path("year").asInt(); }

    public double k401Limit() { return table.path("k401Limit").asDouble(); }

    public boolean knowsState(String code) {
        return code != null && table.path("states").has(code.toUpperCase(Locale.ROOT));
    }

    /**
     * @param gross        yearly salary
     * @param state        two-letter code ("VA"); unknown → no state tax
     * @param k401Percent  of salary into a pre-tax 401(k) (capped at the yearly limit)
     * @param preTaxHealth yearly pre-tax health premiums (lower income and Social Security/Medicare wages)
     */
    public Result calculate(double gross, String state, double k401Percent, double preTaxHealth) {
        gross = Math.max(0, gross);
        double k401 = Math.min(gross * Math.max(0, k401Percent) / 100.0, k401Limit());
        double health = Math.min(Math.max(0, preTaxHealth), gross - k401);

        // federal: wages minus pre-tax 401(k) and health, minus the standard deduction
        JsonNode federal = table.path("federal");
        double federalTaxable = Math.max(0, gross - k401 - health - federal.path("standardDeduction").asDouble());
        double federalTax = bracketTax(federal.path("brackets"), federalTaxable);

        // Social Security and Medicare: health premiums aren't wages for these, 401(k) money is
        JsonNode fica = table.path("fica");
        double ficaWages = gross - health;
        double socialSecurity = Math.min(ficaWages, fica.path("socialSecurityWageBase").asDouble()) * fica.path("socialSecurityRate").asDouble();
        double medicare = ficaWages * fica.path("medicareRate").asDouble()
                + Math.max(0, ficaWages - fica.path("additionalMedicareThreshold").asDouble()) * fica.path("additionalMedicareRate").asDouble();

        // state
        String code = state == null ? "" : state.toUpperCase(Locale.ROOT);
        JsonNode s = table.path("states").path(code);
        double stateTax = 0;
        if (!s.isMissingNode()) {
            boolean deduct401k = s.path("deduct401k").asBoolean(true); // Pennsylvania taxes 401(k) money
            double wages = gross - health - (deduct401k ? k401 : 0);
            double exemption = s.path("exemption").asDouble(0);
            JsonNode phaseout = s.path("exemptionPhaseout");
            if (!phaseout.isMissingNode()) {   // Connecticut: the exemption shrinks as income rises
                double start = phaseout.path("start").asDouble(), end = phaseout.path("end").asDouble();
                double share = wages <= start ? 1 : wages >= end ? 0 : (end - wages) / (end - start);
                exemption *= share;
            }
            double taxable = Math.max(0, wages - s.path("standardDeduction").asDouble(0) - exemption);
            double credit = s.path("credit").asDouble(0);
            JsonNode creditPhaseout = s.path("creditPhaseout");
            if (!creditPhaseout.isMissingNode()) {   // Utah: the taxpayer credit shrinks as income rises
                credit = Math.max(0, credit - Math.max(0, wages - creditPhaseout.path("start").asDouble())
                        * creditPhaseout.path("rate").asDouble());
            }
            stateTax = Math.max(0, bracketTax(s.path("brackets"), taxable) - credit);
        }

        double takeHome = gross - k401 - health - federalTax - socialSecurity - medicare - stateTax;
        return new Result(gross, k401, health, federalTax, socialSecurity, medicare, stateTax, takeHome,
                code, s.path("name").asText(null), s.path("note").asText(null), year());
    }

    /** brackets are [{"over": 0, "rate": .1}, {"over": 12400, "rate": .12}, ...] */
    static double bracketTax(JsonNode brackets, double income) {
        double tax = 0;
        for (int i = 0; i < brackets.size(); i++) {
            double from = brackets.get(i).path("over").asDouble();
            if (income <= from) break;
            double to = i + 1 < brackets.size() ? brackets.get(i + 1).path("over").asDouble() : Double.MAX_VALUE;
            tax += (Math.min(income, to) - from) * brackets.get(i).path("rate").asDouble();
        }
        return tax;
    }

    /** "Columbus, OH" or "Columbus, Ohio" → "OH" */
    public String stateCode(String location) {
        if (location == null) return null;
        String[] parts = location.split(",");
        String last = parts[parts.length - 1].strip();
        if (knowsState(last)) return last.toUpperCase(Locale.ROOT);
        var states = table.path("states").fields();
        while (states.hasNext()) {
            var entry = states.next();
            if (entry.getValue().path("name").asText().equalsIgnoreCase(last)) return entry.getKey();
        }
        return null;
    }

    public JsonNode states() { return table.path("states"); }

    static double round(double v) { return Math.round(v * 100) / 100.0; }
}
