import hunt.http.client;
import core.time;
import core.stdc.stdlib : exit;
import moexparser;
import portfolio;
import bondshelpers;
import std.typecons : Tuple;
import std.algorithm;

void PrintBondsExtToFile(const BondExt[] aBonds, string aFileName)
{
    File file = File(aFileName, "w");

    PrintObjs!BondExt(aBonds, file);
    file.close();
}

Response TakeDataFromMoex(string urlStr, HttpClient aClient)
{
    writeln(urlStr);
    Request request = new RequestBuilder()
        .url(urlStr)
        .build();

    Response response = aClient.newCall(request).execute();

    return response;
}

alias BondsGroups = Tuple!(BondExt[] , "uninteresting", BondExt[], "interesting");

BondsGroups FilterBondsByGroups(const BondExt[] aBonds, const double aDepositRate, long aYearsCount, double aBrokerTransactionFee)
{
    // TODO: разобраться с рейтингами облигаций.
    // TODO: получить рыночные данные.
    BondExt[] uninteresting;
    BondExt[] moreThanDeposit;

    const long year = 365;
    const long years = year * aYearsCount;
    const double moreThanDepositRate = 0.02;
    const auto today = cast(Date)Clock.currTime();

    foreach (const bond; aBonds)
    {
        const double bondActualPrice = GetBondActualPrice(bond);

        BondExt ext = bond;
        ext.HasAmortization = (ext.LOTVALUE != ext.FACEVALUE);        

        const auto couponCount = GetCouponCount(bond.MATDATE, bond.COUPONPERIOD, today);
        const auto commonSimpleYieldToMaturity = CalcCommonSimpleYield(
            couponCount,
            ext.COUPONVALUE,
            ext.FACEVALUE,
            bondActualPrice,
            aBrokerTransactionFee,
            ext.ACCRUEDINT);
        const auto simpleYieldToMaturityPerYear = CalcSimpleYieldPerYear(
            commonSimpleYieldToMaturity,
            today,
            ext.MATDATE);

        ext.CommonSimpleYieldToMaturity = commonSimpleYieldToMaturity * 100;

        ext.SimpleYieldToMaturityPerYear = simpleYieldToMaturityPerYear * 100;
    
        const long days = GetDaysBetweenDates(ext.MATDATE, today);
        if (ext.FACEVALUE > 10000
            || days < year
            || days > years
            || simpleYieldToMaturityPerYear <= aDepositRate + moreThanDepositRate)
        {
            uninteresting ~= ext;
        }
        else
        {
            moreThanDeposit ~= ext;
        }
    }

    return BondsGroups(uninteresting, moreThanDeposit);
}

AmortData[] TakeAmortizationDataForBond(HttpClient aClient, const string aIsin, const Date aFrom, const Date aTill)
{
    AmortData[] allAmortsData;

    // Получаем курсор, чтобы запрашивать данные по частям.
    string isinWithSlash = aIsin.length > 0
        ? "/" ~ aIsin
        : "";

    auto amortCursorQuery = "http://iss.moex.com/iss/statistics/engines/stock/markets/bonds/bondization"
        ~ isinWithSlash  ~ ".json?iss.json=extended&iss.meta=off&iss.only=amortizations.cursor&from="
        ~ aFrom.toISOExtString()
        ~ "&till=" ~ aTill.toISOExtString();

    auto jsonStr = QueryData(aClient, amortCursorQuery);

    MoexCursor cursor = ParseMoexCursor(jsonStr, "amortizations");

    PrintObj!MoexCursor(cursor, stdout);

    for (; cursor.INDEX < cursor.TOTAL; cursor.INDEX += cursor.PAGESIZE)
    {
        auto amortQuery = "http://iss.moex.com/iss/statistics/engines/stock/markets/bonds/bondization"
         ~ isinWithSlash  ~".json?iss.json=extended&iss.meta=off&iss.only=amortizations&from="
         ~ aFrom.toISOExtString()
         ~ "&till=" ~ aTill.toISOExtString()
        ~ "&start=" ~ to!string(cursor.INDEX) ~ "&limit=" ~ to!string(cursor.PAGESIZE);

        auto jsonStrAmort = QueryData(aClient, amortQuery);

        auto amortsData = ParseAmortData(jsonStrAmort);

        allAmortsData ~= amortsData;
    }

    PrintObjectsToFile(allAmortsData, "../log/amortizationInfo"~ aIsin ~".txt");
    return allAmortsData;
}

CouponData[] TakeCouponDataForBond(HttpClient aClient, const string aIsin, const Date aFrom, const Date aTill)
{
    CouponData[] allCouponsData;

    string isinWithSlash = (aIsin.length > 0)
        ? "/" ~ aIsin
        : "";

    // Получаем курсор, чтобы запрашивать данные по частям.
    auto couponCursorQuery = "http://iss.moex.com/iss/statistics/engines/stock/markets/bonds/bondization"
        ~ isinWithSlash  ~".json?iss.json=extended&iss.meta=off&iss.only=coupons.cursor&from="
        ~ aFrom.toISOExtString()
        ~ "&till=" ~ aTill.toISOExtString();

    auto jsonStr = QueryData(aClient, couponCursorQuery);

    MoexCursor cursor = ParseMoexCursor(jsonStr, "coupons");

    PrintObj!MoexCursor(cursor, stdout);

    for (; cursor.INDEX < cursor.TOTAL; cursor.INDEX += cursor.PAGESIZE)
    {
        auto couponQuery = "http://iss.moex.com/iss/statistics/engines/stock/markets/bonds/bondization"
         ~ isinWithSlash  ~".json?iss.json=extended&iss.meta=off&iss.only=coupons&from="
         ~ aFrom.toISOExtString()
         ~ "&till=" ~ aTill.toISOExtString()
        ~ "&start=" ~ to!string(cursor.INDEX) ~ "&limit=" ~ to!string(cursor.PAGESIZE);

        auto jsonStrCoupon = QueryData(aClient, couponQuery);

        auto couponData = ParseCouponData(jsonStrCoupon);

        allCouponsData ~= couponData;
    }

    PrintObjectsToFile(allCouponsData, "../log/couponsInfo"~ aIsin ~".txt");
    return allCouponsData;
}

string QueryData(HttpClient aClient, string aQuery)
{
    auto response = TakeDataFromMoex(aQuery, aClient);

    auto statusCode = response.getStatus();

    const int httpOk = 200;
    if (statusCode != httpOk)
    {
        printf("Unexpected status code: %d\n", statusCode);
        exit(1);
    }

    HttpBody resbody =  response.getBody();
    return resbody.asString();
}

BondExt[] QueryBonds(HttpClient aClient, string aQuery)
{
    auto jsonStr = QueryData(aClient, aQuery);
    return ParseBonds(jsonStr);
}

void SortBonds(ref BondExt[] aBonds)
{
    auto myComp = (BondExt x, BondExt y)
    {
        if (x.SimpleYieldToMaturityPerYear > y.SimpleYieldToMaturityPerYear)
        {
            return true;
        }
        
        if (x.SimpleYieldToMaturityPerYear < y.SimpleYieldToMaturityPerYear)
        {
            return false;
        }

        return x.MATDATE < y.MATDATE;
    };

    aBonds.sort!(myComp);
}

Date GetMaxDate(BondExt[] aBonds, const Date aFrom)
{
    auto date = aBonds.maxElement!(x => x.MATDATE).MATDATE;

    return max(date, aFrom);
}

void PrintByLevels(const BondExt[] aBonds, const string aFilePrefix)
{
    string firstPart = "../log/" ~ aFilePrefix;

    BondExt[] level1, level2, level3;

    foreach (const b; aBonds)
    {
        switch (b.LISTLEVEL)
        {
        case 1:
            level1 ~= b;
            break;
        case 2:
            level2 ~= b;
            break;
        case 3:
            level3 ~= b;
            break;
        default:
            writeln("Wrong list level, SECID: %s", b.SECID);
            break;
        }
    }

    SortBonds(level1);
    SortBonds(level2);
    SortBonds(level3);


    WriteToCsv!BondExt(firstPart ~ "-level1.csv", level1);
    WriteToCsv!BondExt(firstPart ~ "-level2.csv", level2);
    WriteToCsv!BondExt(firstPart ~ "-level3.csv", level3);


    PrintBondsExtToFile(level1, firstPart ~ "-level1.txt");
    PrintBondsExtToFile(level2, firstPart ~ "-level2.txt");
    PrintBondsExtToFile(level3, firstPart ~ "-level3.txt");
}

void ProcessBonds(
    HttpClient aClient,
    const BondExt[] allBonds,
    const long aYearsCount,
    const double aDepositRate,
    const double aBrokertTransactionFee)
{
    auto groups = FilterBondsByGroups(allBonds, aDepositRate, aYearsCount, aBrokertTransactionFee);

    BondExt[] interesting = groups.interesting;
    BondExt[] uninteresting = groups.uninteresting;

    BondExt[] moreThanDeposit;

    foreach (bond; interesting)
    {
        const auto securityQuery = "http://iss.moex.com/iss/securities/"
            ~ bond.SECID ~ ".json?iss.only=description&description.columns=name,value&iss.meta=off&iss.json=extended";
        auto jsonStr = QueryData(aClient, securityQuery);
        const auto secDesc = ParseSecurityDesc(jsonStr);

        bond.ISQUALIFIEDINVESTORS = secDesc.ISQUALIFIEDINVESTORS;
        bond.EARLYREPAYMENT = secDesc.EARLYREPAYMENT;

        if (bond.ISQUALIFIEDINVESTORS)
        {
            uninteresting ~= bond;
        }
        else
        {
            moreThanDeposit ~= bond;
        }
    }

    PrintBondsExtToFile(uninteresting, "../log/uniteresting.txt");

    const auto today = GetToday();

    Date minDate = today, maxDate = GetMaxDate(moreThanDeposit, today);

    writeln(format("minDate:%s, maxDate:%s", minDate.toISOExtString(), maxDate.toISOExtString()));

    auto allAmortsData = TakeAmortizationDataForBond(aClient, "", minDate, maxDate);

    AmortData[][string] amortsByISIN;

    foreach (data; allAmortsData)
    {
        amortsByISIN[data.isin] ~= data;
    }

    BondExt[] withAmort;
    BondExt[] withoutAmort;

    foreach (b; moreThanDeposit)
    {
        if (b.ISIN in amortsByISIN)
        {
            b.HasAmortization = true;
            withAmort ~= b;
        }
        else
        {
            withoutAmort ~= b;
        }
    }

    PrintByLevels(withoutAmort, "withoutAmort");

    foreach (b; withAmort)
    {
        const auto couponData = TakeCouponDataForBond(aClient, b.SECID, minDate, b.MATDATE);
        double couponAmount = 0.0;
        foreach (coupon; couponData)
        {
            couponAmount += coupon.value_rub;
        }

        const auto commonSimpleYieldToMaturity = CalcCommonSimpleYield(
            couponAmount,
            b.FACEVALUE,
            GetBondActualPrice(b),
            aBrokertTransactionFee,
            b.ACCRUEDINT);
        
        const auto simpleYieldToMaturityPerYear = CalcSimpleYieldPerYear(
            commonSimpleYieldToMaturity,
            today,
            b.MATDATE);

        // Учёт лучше вести по CommonSimpleYieldToMaturity, так как из-за амортизации среднегодовой доход будет низким.
        b.CommonSimpleYieldToMaturity = 100 * commonSimpleYieldToMaturity;
        b.SimpleYieldToMaturityPerYear = 100 * simpleYieldToMaturityPerYear;
    }

    PrintByLevels(withAmort, "withAmort");
}

void StopEventLoop()
{
    import hunt.net.NetUtil;
    NetUtil.eventLoop.stop();
}

double GetYieldIfSellToday(const Deal aDealInfo, const BondExt aBondInfo)
{
    // TODO: проверить формулу
    const double brokerTax = 0.05 * 0.01;
    const double allInCost = aDealInfo.BuyPrice * (1 + brokerTax) * aDealInfo.Quantity + aDealInfo.AccruedIntQty;

    const double prevPrice = quantize!floor(aBondInfo.FACEVALUE * aBondInfo.PREVWAPRICE / 100, aBondInfo.MINSTEP);
    const double sellPx = prevPrice + aBondInfo.ACCRUEDINT;

    const double sellTax = aDealInfo.BuyPrice >= sellPx ? 1 : 0.87;

    const double sellCost = (prevPrice * (1 - brokerTax) + aBondInfo.ACCRUEDINT) * aDealInfo.Quantity * sellTax;

    return sellCost + aDealInfo.CouponValueInQty - allInCost;
}

alias CouponPaymentInfo = Tuple!(
    double, "oldCouponAmount",
    double, "newCouponAmount",
    double, "oldFaceValue");

// deprecated. Можно получать графики выплат и амортизаций от биржи.
CouponPaymentInfo GetCouponPaymentInfoForAmorts(
    const AmortData[] aAmortData,
    const Deal aProcessedDeal,
    const double aPeriod,
    const double aCurrentFaceValue,
    const double aCouponPersent,
    const Date aToday)
{
    CouponPaymentInfo info;
    info.oldCouponAmount = 0.0;
    info.newCouponAmount = 0.0;
    info.oldFaceValue = aCurrentFaceValue;

    int oldCouponsCount = 0;

    if (aProcessedDeal.CouponPaidCount > 0)
    {
        for (; oldCouponsCount < aAmortData.length && aAmortData[oldCouponsCount].amortdate < aToday; ++oldCouponsCount){}

        // Назад во времени

        // Если амортизации ещё не было.
        if (oldCouponsCount == 0)
        {
            info.oldCouponAmount = quantize!floor(
                aCurrentFaceValue * aCouponPersent / aPeriod * aProcessedDeal.CouponPaidCount, 0.01);
        }
        else
        {
            for (int index = oldCouponsCount - 1; index >= 0 ; --index)
            {
                info.oldFaceValue += aAmortData[index].value_rub;
                info.oldCouponAmount += info.oldFaceValue * aCouponPersent;
            }
        }
    }

    double currentFaceValue = aCurrentFaceValue;

    // Вперед во времени
    for (int index = oldCouponsCount; index < aAmortData.length; ++index)
    {
        info.newCouponAmount += currentFaceValue * aCouponPersent;
        currentFaceValue -= aAmortData[index].value_rub;
    }

    return info;
}

CouponPaymentInfo GetCouponPaymentInfoForAmortsAndCoupons(
    const AmortData[] aAmortData,
    const CouponData[] aCouponData,
    const Deal aProcessedDeal,
    const double aCurrentFaceValue,
    const Date aToday)
{
    CouponPaymentInfo info;
    info.oldCouponAmount = 0.0;
    info.newCouponAmount = 0.0;
    info.oldFaceValue = aCurrentFaceValue;

    for (int index; index < aAmortData.length && aAmortData[index].amortdate < aToday; ++index)
    {
        info.oldFaceValue += aAmortData[index].value_rub;
    }

    long newCouponsIndex = 0;
    if (aProcessedDeal.CouponPaidCount > 0)
    {
        // Назад во времени
        long oldCouponsIndex = 0;

        for (; oldCouponsIndex < aCouponData.length && aCouponData[oldCouponsIndex].coupondate <= aProcessedDeal.BuyDate
             ; ++oldCouponsIndex){}

        newCouponsIndex = oldCouponsIndex + aProcessedDeal.CouponPaidCount;

        foreach (long index; oldCouponsIndex .. newCouponsIndex)
        {
            info.oldCouponAmount += aCouponData[index].value_rub;
        }
    }

    for (; newCouponsIndex < aCouponData.length; ++newCouponsIndex)
    {
        info.newCouponAmount += aCouponData[newCouponsIndex].value_rub;
    }

    return info;
}

CouponPaymentInfo GetCouponPaymentInfoCommon(
    HttpClient aClient,
    const Deal aProcessedDeal,
    const BondExt aBond,
    const Date aToday)
{
    CouponPaymentInfo info;

    if (!aProcessedDeal.HasAmortization)
    {
        const auto couponCount = GetCouponCount(aBond.MATDATE, aBond.COUPONPERIOD, aProcessedDeal.BuyDate);

        info.oldFaceValue = aBond.FACEVALUE;
        info.oldCouponAmount = aBond.COUPONVALUE * aProcessedDeal.CouponPaidCount;
        info.newCouponAmount = couponCount * aBond.COUPONVALUE;
        return info;
    }

    auto amortsData = TakeAmortizationDataForBond(
        aClient,
        aProcessedDeal.ISIN,
        aProcessedDeal.BuyDate,
        aBond.MATDATE);

    if (amortsData.length == 0)
    {
        writefln("ISIN %s: Нет данных по графику амортизационных выплат.", aBond.ISIN);
    }

    auto couponsData = TakeCouponDataForBond(
        aClient,
        aProcessedDeal.ISIN,
        aProcessedDeal.BuyDate,
        aBond.MATDATE);

    if (couponsData.length == 0)
    {
        writefln("ISIN %s: Нет данных по графику купонных выплат.", aBond.ISIN);
    }

    return GetCouponPaymentInfoForAmortsAndCoupons(
        amortsData,
        couponsData,
        aProcessedDeal,
        aBond.FACEVALUE,
        aToday);
}

void ProcessPortfolio(
    HttpClient aClient,
    const string aFileName,
    const Deal[] aDeals,
    const BondExt[] aBonds,
    const double aBrokerTransactionFee)
{
    // Простая обработка портфеля без амортизаций
    BondExt[string] bondsByIsin;

    foreach (bond; aBonds)
    {
        bondsByIsin[bond.ISIN] = bond;
    }

    Deal[] processedDeals;
    const auto today = GetToday();

    foreach (const deal; aDeals)
    {
        Deal processedDeal = deal;

        if (processedDeal.ISIN in bondsByIsin)
        {
            auto bond = bondsByIsin[deal.ISIN];
            const auto accruedIntForOne = processedDeal.AccruedIntQty / processedDeal.Quantity;

            processedDeal.MaturityDate = bond.MATDATE;

            // число выплаченных купонов
            processedDeal.CouponPaidCount = GetCouponPaidCount(
                processedDeal.BuyDate,
                today,
                bond.MATDATE,
                bond.COUPONPERIOD);

            const auto info = GetCouponPaymentInfoCommon(aClient, processedDeal, bond, today);

            if (isNaN(info.oldFaceValue))
            {
                continue;
            }

            processedDeal.FaceValuePaid = bond.FACEVALUE - info.oldFaceValue;

            const auto couponAmount = info.oldCouponAmount + info.newCouponAmount;

            const double commonSimpleYield = CalcCommonSimpleYield(
                couponAmount,
                info.oldFaceValue,
                processedDeal.BuyPrice,
                aBrokerTransactionFee,
                accruedIntForOne);

            processedDeal.CommonSimpleYieldToMaturity = 100 * commonSimpleYield;

            processedDeal.SimpleYieldToMaturityPerYear = 100 * CalcSimpleYieldPerYear(
                commonSimpleYield,
                processedDeal.BuyDate,
                bond.MATDATE);
            
            // объем выплаченных купонов
            if ( processedDeal.CouponPaidCount > 0)
            {
                const auto couponQty =  info.oldCouponAmount * processedDeal.Quantity;
                processedDeal.CouponValueInQty = couponQty * 0.87 - processedDeal.AccruedIntQty;
            }

            processedDeal.YieldIfSellToday = GetYieldIfSellToday(processedDeal, bond);

            processedDeals ~= processedDeal;
        }
    }

    WriteToCsv!Deal(aFileName, processedDeals);
}

void main()
{
    const double brokerTransactionFee = 0.01 * 0.05;

    HttpClient client = new HttpClient();

    const auto securitiesQuery = "http://iss.moex.com/iss/engines/stock/markets/bonds/securities.json?iss.json=extended&iss.only=securities&iss.meta=on";
    const auto allBonds = QueryBonds(client, securitiesQuery);

    // Взять и обработать портфель на предмет прошлой доходности и перспектив в зависимости от deals, bonds.
    const string portfolioFilePath = "../Report.csv";
    const string processedPortfolioFilePath = "../log/reports.csv";
    const auto deals = ImportPortfolio(portfolioFilePath);
    ProcessPortfolio(client, processedPortfolioFilePath, deals, allBonds, brokerTransactionFee);

    const long yearsCount = 2;
    const double depositRate = 0.04;

    ProcessBonds(client, allBonds, yearsCount, depositRate, brokerTransactionFee);

    StopEventLoop();

    exit(0);
}