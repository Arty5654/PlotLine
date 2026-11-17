package com.plotline.backend.categorize;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

/**
 * Narrower categories inside a broad one (Alcohol & Bars inside Eating Out, Parking inside
 * Transportation...). A transaction goes to one only when the person's budget has it; otherwise it
 * stays in the broad category.
 *
 * Each knows the bank labels that belong to it and the business names to look for. When the bank's
 * label belongs to some niche, the label decides (a "COFFEE BAR" labeled coffee isn't a bar);
 * otherwise the name does, and only for transactions already sorted into one of its broad types (a
 * "BAR HARBOR" hotel isn't a bar).
 */
final class NicheCategories {

    /**
     * @param name       the category's name in the app
     * @param parents    the broad types (Categorizer.TYPE_*) whose transactions can go here
     * @param names      what a budget category is called to count as this one
     * @param bankLabels Plaid detailed categories that belong here
     * @param merchants  business names that belong here (upper-case match), or null
     * @param nameFirst  the name decides even when the bank's label belongs to another niche
     *                   (a DoorDash order the bank labels fast food is still delivery)
     */
    record Niche(String name, Set<String> parents, Pattern names, Set<String> bankLabels, Pattern merchants, boolean nameFirst) { }

    /** how it was matched: "bank" (its label) or "store" (the business name) */
    record Match(Niche niche, String how) { }

    private static Niche niche(String name, Set<String> parents, String names, Set<String> labels, String merchants) {
        return new Niche(name, parents, Pattern.compile(names, Pattern.CASE_INSENSITIVE), labels,
                merchants == null ? null : Pattern.compile(merchants), false);
    }

    private static Niche nameFirst(String name, Set<String> parents, String names, String merchants) {
        return new Niche(name, parents, Pattern.compile(names, Pattern.CASE_INSENSITIVE), Set.of(), Pattern.compile(merchants), true);
    }

    private static final String DINING = "DINING", GROCERY = "GROCERY", TRANSPORT = "TRANSPORT", SUBSCRIPTION = "SUBSCRIPTION",
            ENTERTAINMENT = "ENTERTAINMENT", MEDICAL = "MEDICAL", SHOPPING = "SHOPPING", PERSONAL = "PERSONAL",
            UTILITIES = "UTILITIES", PHONE = "PHONE", TRAVEL = "TRAVEL", HOME = "HOME", GIFTS = "GIFTS", TAXES = "TAXES",
            SERVICES = "SERVICES";

    /** in order: when a transaction fits more than one the person has, the first wins */
    static final List<Niche> ALL = List.of(
            // eating and drinking
            nameFirst("Food Delivery", Set.of(DINING, GROCERY), "deliver|doordash|uber ?eats|grubhub",
                    "DOORDASH|UBER ?EATS|GRUBHUB|POSTMATES|SEAMLESS|CAVIAR"),
            niche("Coffee", Set.of(DINING), "coffee|\\bcaf[eé]s?\\b|espresso|starbucks", Set.of("FOOD_AND_DRINK_COFFEE"),
                    "STARBUCKS|DUNKIN|PEET'?S|DUTCH BROS|TIM HORTONS|BLUE BOTTLE|CARIBOU|COFFEE|ESPRESSO"),
            niche("Alcohol & Bars", Set.of(DINING, GROCERY), "alcohol|\\bbars?\\b|liquor|\\bbeers?\\b|\\bwines?\\b|\\bdrinks?\\b|\\bpubs?\\b|booze|nightlife",
                    Set.of("FOOD_AND_DRINK_BEER_WINE_AND_LIQUOR"),
                    "(?<!SUSHI |SALAD |JUICE |COFFEE |ESPRESSO |SNACK |OATMEAL |RAW |NAIL |BROW |BLOW ?DRY |LASH )\\bBAR\\b(?![- ]?(&|AND|N)[- ]?GRILL|-B-Q)"
                            + "|\\bPUB\\b|TAVERN|SALOON|TAPROOM|TAP ROOM|BREWERY|BREWING|BREWPUB|\\bLOUNGE\\b|WINERY|\\bWINES?\\b|LIQUOR|SPIRITS|\\bBEER|CANTINA|BIERGARTEN"),
            niche("Fast Food", Set.of(DINING), "fast ?food", Set.of("FOOD_AND_DRINK_FAST_FOOD"),
                    "MCDONALD|TACO BELL|WENDY'?S|BURGER KING|\\bKFC\\b|POPEYE|CHICK-?FIL-?A|CHICKFILA|\\bSUBWAY\\b|FIVE GUYS|SHAKE SHACK|IN-N-OUT"
                            + "|\\bSONIC\\b|\\bARBY|JACK IN THE BOX|CARL'?S JR|DAIRY QUEEN|WHATABURGER|DEL TACO|CHIPOTLE|PANDA EXPRESS|DOMINO|PIZZA HUT|PAPA JOHN|LITTLE CAESAR"),
            // getting around
            niche("Parking", Set.of(TRANSPORT), "parking", Set.of("TRANSPORTATION_PARKING"),
                    "PARKING|PARKMOBILE|PARK MOBILE|SPOTHERO|PAYBYPHONE|PARKWHIZ|LAZ PARK"),
            niche("Tolls", Set.of(TRANSPORT), "\\btolls?\\b", Set.of("TRANSPORTATION_TOLLS"),
                    "E-?Z ?PASS|SUNPASS|FASTRAK|I-?PASS|PEACH PASS|TXTAG|\\bNTTA\\b|\\bTOLL"),
            niche("Rideshare", Set.of(TRANSPORT), "ride ?share|\\buber\\b|\\blyft\\b|taxi|\\bcabs?\\b", Set.of("TRANSPORTATION_TAXIS_AND_RIDE_SHARES"),
                    "\\bUBER\\b(?! ?EATS)|\\bLYFT\\b|TAXI|\\bCAB\\b"),
            niche("Public Transit", Set.of(TRANSPORT), "transit|\\bmetro\\b|subway|\\bbus(es)?\\b|\\btrains?\\b", Set.of("TRANSPORTATION_PUBLIC_TRANSIT"),
                    "WMATA|\\bMTA\\b|\\bBART\\b|SEPTA|MBTA|\\bCTA\\b|MARTA|SMARTRIP|CLIPPER|VENTRA|TRANSIT"),
            // streaming, music, games
            niche("Music", Set.of(SUBSCRIPTION, ENTERTAINMENT, SHOPPING), "\\bmusic\\b|spotify", Set.of("ENTERTAINMENT_MUSIC_AND_AUDIO"),
                    "SPOTIFY|APPLE MUSIC|PANDORA|TIDAL|GUITAR CENTER|SAM ASH"),
            // not by the bank's label: it puts movie theaters there too
            nameFirst("Streaming Services", Set.of(SUBSCRIPTION, ENTERTAINMENT), "streaming|netflix",
                    "NETFLIX|HULU|DISNEY|\\bHBO|\\bMAX\\b|PEACOCK|PARAMOUNT|SPOTIFY|APPLE MUSIC|YOUTUBE (PREMIUM|MUSIC|TV)|SIRIUS|PANDORA|CRUNCHYROLL|FUBO|SLING"),
            niche("Gaming", Set.of(ENTERTAINMENT, SHOPPING, SUBSCRIPTION), "gaming|video ?games?|\\bgames\\b", Set.of("ENTERTAINMENT_VIDEO_GAMES"),
                    "STEAM ?(GAMES|POWERED|PURCHASE)|PLAYSTATION|XBOX|NINTENDO|GAMESTOP|EPIC GAMES|ROBLOX|BLIZZARD"),
            // health
            niche("Dental", Set.of(MEDICAL), "dental|dentist|orthodont|teeth", Set.of("MEDICAL_DENTAL_CARE"),
                    "DENTAL|DENTIST|ORTHODONT"),
            niche("Vision", Set.of(MEDICAL, SHOPPING), "vision|\\beyes?\\b|glasses|contacts|optical|optometr", Set.of("MEDICAL_EYE_CARE"),
                    "OPTICAL|OPTOMETR|EYE ?CARE|VISIONWORKS|WARBY|LENSCRAFTERS|1-?800 ?CONTACTS"),
            niche("Pharmacy", Set.of(MEDICAL), "pharmac|prescription|medication|\\bmeds\\b", Set.of("MEDICAL_PHARMACIES_AND_SUPPLEMENTS"),
                    "\\bCVS\\b|WALGREEN|RITE AID|PHARMACY"),
            niche("Therapy", Set.of(MEDICAL, SERVICES), "therap|counsel|mental health", Set.of(),
                    "THERAP|COUNSEL|BETTERHELP|TALKSPACE|PSYCH"),
            // giving
            niche("Gifts", Set.of(GIFTS, SHOPPING), "\\bgifts?\\b|presents", Set.of("GENERAL_MERCHANDISE_GIFTS_AND_NOVELTIES"),
                    "\\bGIFTS?\\b|HALLMARK|1-?800-?FLOWERS|FLORIST|EDIBLE ARRANGEMENTS"),
            niche("Donations", Set.of(GIFTS, TAXES, SERVICES), "donat|charit|tithe|church|giving", Set.of("GOVERNMENT_AND_NON_PROFIT_DONATIONS"),
                    "DONAT|CHARIT|GOFUNDME|RED CROSS|UNICEF|CHURCH|TITHE|MINISTR"),
            // home
            niche("Home Maintenance", Set.of(HOME, SERVICES), "home ?(maint|repair|improvement)|house ?(maint|repair)|hardware|handyman",
                    Set.of("HOME_IMPROVEMENT_REPAIR_AND_MAINTENANCE", "HOME_IMPROVEMENT_HARDWARE"),
                    "HOME DEPOT|LOWE'?S|ACE HARDWARE|MENARDS|TRUE VALUE|HARDWARE|PLUMB|ELECTRICIAN|HVAC|HANDYMAN|ROOFING|PEST CONTROL"),
            niche("Home Decor", Set.of(HOME, SHOPPING), "decor|furniture|furnish", Set.of("HOME_IMPROVEMENT_FURNITURE"),
                    "IKEA|WAYFAIR|HOMEGOODS|POTTERY BARN|CRATE ?(&|AND) ?BARREL|WEST ELM|KIRKLAND'?S|\\bAT HOME\\b|RESTORATION HARDWARE"),
            // shopping
            niche("Clothing", Set.of(SHOPPING), "cloth|apparel|fashion|\\bshoes\\b|wardrobe", Set.of("GENERAL_MERCHANDISE_CLOTHING_AND_ACCESSORIES"),
                    "OLD NAVY|\\bGAP\\b|\\bH ?& ?M\\b|\\bZARA\\b|UNIQLO|NORDSTROM|TJ ?MAXX|MARSHALLS|ROSS STORES|LULULEMON|FOOT LOCKER|AMERICAN EAGLE|\\bNIKE\\b|ADIDAS"),
            niche("Electronics", Set.of(SHOPPING), "electronic|\\btech\\b|gadget", Set.of("GENERAL_MERCHANDISE_ELECTRONICS"),
                    "BEST ?BUY|MICRO CENTER|\\bB ?& ?H\\b|NEWEGG"),
            niche("Books", Set.of(SHOPPING, ENTERTAINMENT), "\\bbooks?\\b|reading|kindle", Set.of("GENERAL_MERCHANDISE_BOOKSTORES_AND_NEWSSTANDS"),
                    "BARNES|BOOKS?\\b|BOOKSTORE|KINDLE"),
            niche("Baby Supplies", Set.of(SHOPPING, GROCERY), "baby|diaper|infant|newborn", Set.of(),
                    "BUY ?BUY ?BABY|CARTER'?S|OSHKOSH|DIAPER|\\bBABY"),
            // personal care: haircuts by name only (the bank's hair-and-beauty label includes nails and makeup)
            niche("Haircuts", Set.of(PERSONAL), "haircuts?|\\bhair\\b|barber|salon", Set.of(),
                    "BARBER|SALON|SUPERCUTS|GREAT CLIPS|SPORT CLIPS|FANTASTIC SAMS|\\bHAIR"),
            niche("Laundry", Set.of(PERSONAL, SERVICES), "laundry|dry ?clean", Set.of("PERSONAL_CARE_LAUNDRY_AND_DRY_CLEANING"),
                    "LAUNDR|DRY ?CLEAN|CLEANERS|CSC SERVICEWORKS"),
            // bills
            niche("Internet", Set.of(UTILITIES, PHONE), "internet|wi-?fi|broadband|\\bcable\\b", Set.of("RENT_AND_UTILITIES_INTERNET_AND_CABLE"),
                    "COMCAST|XFINITY|SPECTRUM|COX COMM|\\bFIOS\\b|CENTURYLINK|FRONTIER COMM|OPTIMUM|STARLINK|GOOGLE FIBER"),
            niche("Electric", Set.of(UTILITIES), "electric|\\bpower\\b|energy", Set.of("RENT_AND_UTILITIES_GAS_AND_ELECTRICITY"),
                    "ELECTRIC|ENERGY|\\bPOWER\\b|DOMINION|PEPCO|\\bBGE\\b|PG ?& ?E|CON ?ED"),
            niche("Water", Set.of(UTILITIES), "water|sewer|trash|garbage",
                    Set.of("RENT_AND_UTILITIES_WATER", "RENT_AND_UTILITIES_SEWAGE_AND_WASTE_MANAGEMENT"),
                    "WATER|SEWER|WASTE MANAGEMENT|REPUBLIC SERVICES"),
            // travel
            niche("Flights", Set.of(TRAVEL), "flights?|airfare|airline|plane tickets?", Set.of("TRAVEL_FLIGHTS"),
                    "AIRLINE|AIRWAYS|DELTA AIR|UNITED AIR|AMERICAN AIR|SOUTHWEST AIR|JETBLUE|SPIRIT AIR|ALASKA AIR"),
            niche("Hotels", Set.of(TRAVEL), "hotels?|lodging|airbnb|accommodation", Set.of("TRAVEL_LODGING"),
                    "HOTEL|MARRIOTT|HILTON|HYATT|AIRBNB|VRBO|HOLIDAY INN|\\bINN\\b|RESORT|MOTEL"));

    /** every bank label that belongs to some niche */
    private static final Set<String> NICHE_LABELS = ALL.stream().flatMap(n -> n.bankLabels().stream()).collect(Collectors.toSet());

    private static final Map<String, Optional<Niche>> BY_NAME = new ConcurrentHashMap<>();

    private NicheCategories() { }

    /** words that make a category the broad one even when it also names a niche ("Eating Out & Drinks", "Medical & Dental") */
    private static final Map<String, Pattern> BROAD_WORDS = Map.ofEntries(
            Map.entry(DINING, Pattern.compile("eating|dining|restaurant|food out", Pattern.CASE_INSENSITIVE)),
            Map.entry(GROCERY, Pattern.compile("grocer", Pattern.CASE_INSENSITIVE)),
            Map.entry(TRANSPORT, Pattern.compile("transportation|getting around", Pattern.CASE_INSENSITIVE)),
            Map.entry(SUBSCRIPTION, Pattern.compile("subscription", Pattern.CASE_INSENSITIVE)),
            Map.entry(ENTERTAINMENT, Pattern.compile("entertainment|\\bfun\\b", Pattern.CASE_INSENSITIVE)),
            Map.entry(MEDICAL, Pattern.compile("medical|doctor", Pattern.CASE_INSENSITIVE)),
            Map.entry(SHOPPING, Pattern.compile("shopping", Pattern.CASE_INSENSITIVE)),
            Map.entry(PERSONAL, Pattern.compile("personal", Pattern.CASE_INSENSITIVE)),
            Map.entry(UTILITIES, Pattern.compile("utilit", Pattern.CASE_INSENSITIVE)),
            Map.entry(TRAVEL, Pattern.compile("travel|vacation", Pattern.CASE_INSENSITIVE)));

    /** the category names the broad one it sits in, so it isn't the niche */
    static boolean broadByName(String category, Niche niche) {
        for (String parent : niche.parents()) {
            Pattern words = BROAD_WORDS.get(parent);
            if (words != null && words.matcher(category).find()) return true;
        }
        return false;
    }

    /** which niche a budget category is by its name (the first that fits), if any */
    static Niche named(String category) {
        if (category == null) return null;
        return BY_NAME.computeIfAbsent(category.strip().toLowerCase(), c -> {
            for (Niche n : ALL) if (n.name().equalsIgnoreCase(c)) return Optional.of(n);
            for (Niche n : ALL) if (n.names().matcher(c).find()) return Optional.of(n);
            return Optional.empty();
        }).orElse(null);
    }

    /** what the less obvious ones mean, for the AI (a restaurant that serves drinks isn't a bar) */
    static final Map<String, String> MEANING = Map.of(
            "Alcohol & Bars", "bars, pubs, taprooms, breweries, wine bars, nightclubs and liquor stores (not restaurants that also serve drinks)",
            "Coffee", "coffee shops and cafes",
            "Fast Food", "fast-food and fast-casual chains (counter service)",
            "Food Delivery", "delivery apps",
            "Home Maintenance", "repairs, hardware stores, plumbers, cleaners for the home",
            "Baby Supplies", "baby stores and baby products",
            "Haircuts", "barbers and hair salons");

    /** where a place's name says what it is (bills, taxes and subscriptions are decided by the bank's labels) */
    private static final Set<String> AI_TYPES = Set.of(DINING, GROCERY, SHOPPING, ENTERTAINMENT, PERSONAL, MEDICAL, HOME, TRAVEL, GIFTS);

    /** the niches the AI picks from for a broad type, by name (none for bills and taxes) */
    static List<String> optionsFor(String broadType) {
        if (broadType == null || !AI_TYPES.contains(broadType)) return List.of();
        return ALL.stream().filter(n -> n.parents().contains(broadType)).map(Niche::name).toList();
    }

    /** the niches a transaction (already sorted into a broad type) fits, best first; the AI's pick only when nothing else fits */
    static List<Match> matching(String detailedLabel, String merchant, String broadType, String aiPick) {
        List<Match> out = matching(detailedLabel, merchant, broadType);
        if (out.isEmpty() && aiPick != null && broadType != null) {
            for (Niche n : ALL) if (n.name().equals(aiPick) && n.parents().contains(broadType)) out.add(new Match(n, "ai"));
        }
        return out;
    }

    /** the niches a transaction (already sorted into a broad type) fits by its label and name, best first */
    static List<Match> matching(String detailedLabel, String merchant, String broadType) {
        List<Match> out = new ArrayList<>();
        if (broadType == null) return out;
        boolean nicheLabel = detailedLabel != null && NICHE_LABELS.contains(detailedLabel);
        String upper = merchant == null ? "" : merchant.toUpperCase();
        for (Niche n : ALL) {
            if (!n.parents().contains(broadType)) continue;
            boolean byName = n.merchants() != null && !upper.isEmpty() && n.merchants().matcher(upper).find();
            if (n.nameFirst() && byName) out.add(new Match(n, "store"));
            else if (nicheLabel && n.bankLabels().contains(detailedLabel)) out.add(new Match(n, "bank"));
            else if (!nicheLabel && byName) out.add(new Match(n, "store"));
        }
        return out;
    }
}
