import hunt.http.client;
import std.math;
import core.time;
import std.algorithm.sorting;
import core.stdc.stdlib : exit;
import moexparser;

void PrintBondsExtToFile(const BondExtension[] aBonds, string aFileName)
{
    File file = File(aFileName, "w");

    foreach(bondExt; aBonds)
    {
        PrintObj!Bond(bondExt.TheBond, file);
        file.writeln(format("%-15s %s%%", "Простая годовая доходность до погашения", bondExt.YieldToMaturity * 100));
        file.writeln(format("%-15s %s", "Амортизация", bondExt.HasAmortization));
    }

    file.close();
}

uint GetCouponCount(const Bond aBondInfo, Date aToday)
{
    // TODO: правильно расчитать число купонов по дате погашения.

    if (aBondInfo.MATDATE == aBondInfo.NEXTCOUPON)
    {
        return 1;
    }

    auto daysDiff = GetDaysBetweenDates(aBondInfo.MATDATE, aToday);
    return cast(uint)daysDiff / cast(uint)aBondInfo.COUPONPERIOD;
}

double GetYearsToMaturityFromToday(Date aMaturityDate, Date aToday)
{
    // TODO: Правильно расчитать число дней до погашения
    auto daysDiff = GetDaysBetweenDates(aMaturityDate, aToday);

    auto years = daysDiff/365.0;
    return years.quantize(0.01);
}

/// Простая годовая доходность до погашения с учётом налогов и сборов
double GetPerYearYieldToMaturity(
    const Bond aBondInfo,
    double aBondActualPrice,
    double aBrokerMonthlyTax,
    double aBrokerTransactionTax,
    Date aToday)
{
    // Коэффициент при налоговой ставке 13%
    const double afterTax = 0.87;

    const uint couponCount = GetCouponCount(aBondInfo, aToday);
    const double shelfLife = GetYearsToMaturityFromToday(aBondInfo.MATDATE, aToday);

    // Сумма купонов за весь срок с учётом налога 13%
    const double couponAmount = aBondInfo.COUPONVALUE * couponCount * afterTax;

    // Полная цена приобретения облигации
    const double allInCost = aBondActualPrice * (1 + aBrokerTransactionTax) + aBrokerMonthlyTax + aBondInfo.ACCRUEDINT;
    
    // Доход с учётом разницы полной цены покупки облигации и номинала
    const double dirtyYield =  couponAmount + aBondInfo.FACEVALUE - allInCost;

    const double perYearYield = dirtyYield / allInCost / shelfLife;

    return perYearYield.quantize(0.001);
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

BondExtension[] FilterBondsByGroups(const Bond[] aBonds, const double aDepositRate, long aYearsCount)
{
    // TODO: разобраться с рейтингами облигаций.
    // TODO: получить рыночные данные.
    BondExtension[] uninteresting;
    BondExtension[] moreThanDeposit;

    const long year = 365;
    const long years = year * aYearsCount;
    const double moreThanDepositRate = 0.02;
    const auto today = cast(Date)Clock.currTime();

    foreach (bond; aBonds)
    {
        if (!IsAllowedBoard(bond.BOARDID)
            || !empty(bond.OFFERDATE)
            || bond.COUPONPERIOD == 0
            || empty(bond.MATDATE)
            || empty(bond.NEXTCOUPON)
            || bond.COUPONPERCENT == 0.0
            || !IsRub(bond.FACEUNIT)
            || !IsRub(bond.CURRENCYID))
        {
            continue;
        }

        // Здесь беру максимальное значение цены
        double bondActualPrice = bond.FACEVALUE;

        if (IsValidPrice(bond.PREVPRICE))
        {
            // Предыдущая цена задаётся в процентах от номинала, поэтому делю на 100
            const double prevPriceAbsolute = quantize(bond.FACEVALUE * bond.PREVPRICE / 100, bond.MINSTEP);

            bondActualPrice = fmax(bondActualPrice, prevPriceAbsolute);
        }

        if (IsValidPrice(bond.PREVWAPRICE))
        {
            const double prevVwapPriceAbsolute = quantize(bond.FACEVALUE * bond.PREVWAPRICE / 100, bond.MINSTEP);

            bondActualPrice = fmax(bondActualPrice, prevVwapPriceAbsolute);
        }

        const double brokerTransactionFee = 0.01 * 0.05;
        const double brokerMonthlyTax = 0;
        const double yieldToMaturity = GetPerYearYieldToMaturity(
            bond,
            bondActualPrice,
            brokerMonthlyTax,
            brokerTransactionFee,
            today);

        const long days = GetDaysBetweenDates(bond.MATDATE, today);
        if (bond.LOTVALUE != bond.FACEVALUE || days < year || days > years)
        {
            BondExtension ext;
            ext.TheBond = bond;
            ext.YieldToMaturity = yieldToMaturity;
            ext.HasAmortization = (bond.LOTVALUE != bond.FACEVALUE);

            uninteresting ~= ext;
            continue;
        }

        if (yieldToMaturity <= aDepositRate + moreThanDepositRate)
        {
            BondExtension ext;
            ext.TheBond = bond;
            ext.YieldToMaturity = yieldToMaturity;

            uninteresting ~= ext;
        }
        else
        {
            BondExtension ext;
            ext.TheBond = bond;
            ext.YieldToMaturity = yieldToMaturity;

            moreThanDeposit ~= ext;
        }
    }

    PrintBondsExtToFile(uninteresting, "../log/uniteresting.txt");
    return moreThanDeposit;
}


AmortData[] TakeAmortizationData(Date aFrom, Date aTill, HttpClient aClient)
{
    AmortData[] allAmortsData;

    // Получаем курсор, чтобы запрашивать данные по частям.
    auto amortCursorQuery = "http://iss.moex.com/iss/statistics/engines/stock/markets/bonds/bondization.json?iss.json=extended&iss.meta=off&iss.only=amortizations.cursor&from=" ~ aFrom.toISOExtString() ~ "&till=" ~ aTill.toISOExtString();
    auto response = TakeDataFromMoex(amortCursorQuery, aClient);
    const int httpOk = 200;
    auto statusCode = response.getStatus();

    if (statusCode != httpOk)
    {
        printf("Unexpected status code: %d\n", statusCode);
        return allAmortsData;
    }

    HttpBody resbody =  response.getBody();
    auto jsonStr = resbody.asString();

    AmortCursor cursor = ParseAmortCursor(jsonStr);

    for (; cursor.INDEX < cursor.TOTAL; cursor.INDEX += cursor.PAGESIZE)
    {
        auto amortQuery = "http://iss.moex.com/iss/statistics/engines/stock/markets/bonds/bondization.json?iss.json=extended&iss.meta=off&iss.only=amortizations&from=" ~ aFrom.toISOExtString() ~ "&till=" ~ aTill.toISOExtString()
        ~ "&start=" ~ to!string(cursor.INDEX) ~ "&limit=" ~ to!string(cursor.PAGESIZE);
        auto responseAmort = TakeDataFromMoex(amortQuery, aClient);
        statusCode = responseAmort.getStatus();
        if (statusCode != httpOk)
        {
            printf("Unexpected status code: %d\n", statusCode);
            return allAmortsData;
        }
        HttpBody resbodyAmort =  responseAmort.getBody();
        auto jsonStrAmort = resbodyAmort.asString();

        auto amortsData = ParseAmortData(jsonStrAmort);

        allAmortsData ~= amortsData;
    }

    PrintObjectsToFile(allAmortsData, "../log/amortizationInfo.txt");
    return allAmortsData;
}

void ProcessBonds(HttpClient aClient, long aYearsCount)
{
    auto securitiesQuery = "http://iss.moex.com/iss/engines/stock/markets/bonds/securities.json?iss.json=extended&iss.only=securities&iss.meta=on";

    auto response = TakeDataFromMoex(securitiesQuery, aClient);

    auto statusCode = response.getStatus();

    const int httpOk = 200;
    if (statusCode != httpOk)
    {
        printf("Unexpected status code: %d\n", statusCode);
        return;
    }

    HttpBody resbody =  response.getBody();
    auto jsonStr = resbody.asString();

    Bond[] bonds = ParseBonds(jsonStr);
    const double depositRate = 0.04;
    BondExtension[] moreThanDeposit = FilterBondsByGroups(bonds, depositRate, aYearsCount);

    const auto today = cast(Date)Clock.currTime();

    const auto prevDay = today - 1.days;
    Date minDate = prevDay, maxDate = today;

    foreach (b; moreThanDeposit)
    {
        auto couponDate = b.TheBond.NEXTCOUPON;
        if (couponDate < minDate || minDate == prevDay)
        {
            minDate = couponDate;
        }

        if (couponDate > maxDate)
        {
            maxDate = couponDate;
        }
    }

    writeln(format("minDate:%s, maxDate:%s", minDate, maxDate));

    AmortData[] allAmortsData = TakeAmortizationData(minDate, maxDate, aClient);

    AmortData[string] amortsByISIN;

    foreach (dta; allAmortsData)
    {
        amortsByISIN[dta.isin] = dta;
    }

    BondExtension[] moreThanDepositWithoutAmort;

    foreach (b; moreThanDeposit)
    {
        if (b.TheBond.ISIN in amortsByISIN)
        {
            b.HasAmortization = true;
        }
        else
        {
            moreThanDepositWithoutAmort ~= b;
        }
    }

    auto myComp = (BondExtension x, BondExtension y)
    {
        if (x.YieldToMaturity > y.YieldToMaturity)
        {
            return true;
        }
        
        if (x.YieldToMaturity < y.YieldToMaturity)
        {
            return false;
        }

        if (x.TheBond.MATDATE < y.TheBond.MATDATE)
        {
            return true;
        }

        if (x.TheBond.MATDATE > y.TheBond.MATDATE)
        {
            return false;
        }

        if (x.TheBond.LISTLEVEL < y.TheBond.LISTLEVEL)
        {
            return true;
        }

        return false;
    };

    moreThanDepositWithoutAmort.sort!(myComp);

    PrintBondsExtToFile(moreThanDepositWithoutAmort, "../log/goodBondsNoAmort.txt");
}

void StopEventLoop()
{
    import hunt.net.NetUtil;
    NetUtil.eventLoop.stop();
}

void main()
{
    HttpClient client = new HttpClient();

    const long yearsCount = 3;
    ProcessBonds(client, yearsCount);

    StopEventLoop();

    exit(0);
}

unittest
{
    ///Расчёт числа купонов

    auto today = Date(2021, 7, 16);
    {
        Bond b;
        b.MATDATE = Date(2022, 6, 15);
        b.COUPONPERIOD = 910;
        b.NEXTCOUPON = Date(2022, 6, 15);
        const auto actual = GetCouponCount(b, today);
        assert(actual == 1);
    }

    {
        Bond b;
        b.MATDATE = Date(2021, 8, 17);
        b.COUPONPERIOD = 31;
        b.NEXTCOUPON = Date(2021, 7, 17);
        const auto actual = GetCouponCount(b, today);
        assert(actual == 2);
    }
}
