import hunt.http.client;
import core.time;
import std.algorithm.sorting;
import core.stdc.stdlib : exit;
import moexparser;
import portfolio;
import bondshelpers;
import std.typecons : Tuple;

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

AmortData[] TakeAmortizationData(Date aFrom, Date aTill, HttpClient aClient)
{
    AmortData[] allAmortsData;

    // Получаем курсор, чтобы запрашивать данные по частям.
    auto amortCursorQuery = "http://iss.moex.com/iss/statistics/engines/stock/markets/bonds/bondization.json?iss.json=extended&iss.meta=off&iss.only=amortizations.cursor&from="
        ~ aFrom.toISOExtString()
        ~ "&till=" ~ aTill.toISOExtString();

    auto jsonStr = QueryData(aClient, amortCursorQuery);

    AmortCursor cursor = ParseAmortCursor(jsonStr);

    PrintObj!AmortCursor(cursor, stdout);

    for (; cursor.INDEX < cursor.TOTAL; cursor.INDEX += cursor.PAGESIZE)
    {
        auto amortQuery = "http://iss.moex.com/iss/statistics/engines/stock/markets/bonds/bondization.json?iss.json=extended&iss.meta=off&iss.only=amortizations&from=" ~ aFrom.toISOExtString() ~ "&till=" ~ aTill.toISOExtString()
        ~ "&start=" ~ to!string(cursor.INDEX) ~ "&limit=" ~ to!string(cursor.PAGESIZE);

        auto jsonStrAmort = QueryData(aClient, amortQuery);

        auto amortsData = ParseAmortData(jsonStrAmort);

        allAmortsData ~= amortsData;
    }

    PrintObjectsToFile(allAmortsData, "../log/amortizationInfo.txt");
    return allAmortsData;
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

        if (x.MATDATE < y.MATDATE)
        {
            return true;
        }

        if (x.MATDATE > y.MATDATE)
        {
            return false;
        }

        if (x.LISTLEVEL < y.LISTLEVEL)
        {
            return true;
        }

        return false;
    };

    aBonds.sort!(myComp);
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

    Date minDate = today, maxDate = today;

    foreach (b; moreThanDeposit)
    {
        if (b.MATDATE > maxDate)
        {
            maxDate = b.MATDATE;
        }
    }

    writeln(format("minDate:%s, maxDate:%s", minDate.toISOExtString(), maxDate.toISOExtString()));

    AmortData[] allAmortsData = TakeAmortizationData(minDate, maxDate, aClient);

    alias ByIsin = AmortData[][string];

    ByIsin amortsByISIN;

    foreach (dta; allAmortsData)
    {
        amortsByISIN[dta.isin] ~= dta;
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

    SortBonds(withoutAmort);
    PrintBondsExtToFile(withoutAmort, "../log/withoutAmort.txt");

    foreach (b; withAmort)
    {
        const auto amortsData = amortsByISIN[b.ISIN];
        // TODO: Научиться обрабатывать облигации с амортизацией, если она не совпадает
        // c датой выплаты купона.
        if (b.NEXTCOUPON == amortsData[0].amortdate)
        {
            const double couponPercent = b.COUPONPERCENT/100;

            // Без учёта налога
            double couponAmount = 0.0;
            double currentFaceValue = b.FACEVALUE;
            foreach (amort; amortsData)
            {
                couponAmount += currentFaceValue * couponPercent;
                currentFaceValue -= amort.value_rub;
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
        else
        {
            writefln("ISIN %s: Дата выплаты купона и дата амортизации различны.", b.ISIN);
            b.CommonSimpleYieldToMaturity = 0;
            b.SimpleYieldToMaturityPerYear = 0;
        }
    }

    SortBonds(withAmort);
    PrintBondsExtToFile(withAmort, "../log/withAmort.txt");
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

void ProcessPortfolio(string aFileName, const Deal[] aDeals, const BondExt[] aBonds, double aBrokerTransactionFee)
{
    // Простая обработка портфеля без амортизаций
    BondExt[string] bondsByIsin;

    foreach (bond; aBonds)
    {
        bondsByIsin[bond.ISIN] = bond;
    }

    Deal[] processedDeals;

    foreach (const deal; aDeals)
    {
        Deal processedDeal = deal;

        if (processedDeal.ISIN in bondsByIsin)
        {
            auto bond = bondsByIsin[deal.ISIN];
            const auto accruedIntForOne = processedDeal.AccruedIntQty / processedDeal.Quantity;

            if (processedDeal.HasAmortization)
            {
                continue;
            }

            const auto couponCount = GetCouponCount(bond.MATDATE, bond.COUPONPERIOD, processedDeal.BuyDate);

            const double commonSimpleYield = CalcCommonSimpleYield(
                couponCount * bond.COUPONVALUE,
                bond.FACEVALUE,
                processedDeal.BuyPrice,
                aBrokerTransactionFee,
                accruedIntForOne);

            processedDeal.CommonSimpleYieldToMaturity = 100 * commonSimpleYield;

            processedDeal.SimpleYieldToMaturityPerYear = 100 * CalcSimpleYieldPerYear(
                commonSimpleYield,
                processedDeal.BuyDate,
                bond.MATDATE);

            // число выплаченных купонов
            processedDeal.CouponPaidCount = GetCouponPaidCount(
                processedDeal.BuyDate,
                GetToday(),
                bond.MATDATE,
                bond.COUPONPERIOD);
            
            // объем выплаченных купонов
            if ( processedDeal.CouponPaidCount > 0)
            {
                const auto couponQty =  bond.COUPONVALUE * processedDeal.CouponPaidCount * processedDeal.Quantity;
                processedDeal.CouponValueInQty = couponQty * 0.87 - processedDeal.AccruedIntQty;
            }

            processedDeal.YieldIfSellToday = GetYieldIfSellToday(processedDeal, bond);

            processedDeals ~= processedDeal;
        }
    }

    File f = File(aFileName, "w");
    PrintObjs!Deal(processedDeals, f);
    f.close();
}

void main()
{
    const double brokerTransactionFee = 0.01 * 0.05;

    const string portfolioFilePath = "../Report.csv";

    const auto deals = ImportPortfolio(portfolioFilePath);

    HttpClient client = new HttpClient();

    const auto securitiesQuery = "http://iss.moex.com/iss/engines/stock/markets/bonds/securities.json?iss.json=extended&iss.only=securities&iss.meta=on";
    const auto allBonds = QueryBonds(client, securitiesQuery);

    // Взять и обработать портфель на предмет прошлой доходности и перспектив в зависимости от deals, bonds.
    const string processedPortfolioFilePath = "../log/reports.txt";
    ProcessPortfolio(processedPortfolioFilePath, deals, allBonds, brokerTransactionFee);

    const long yearsCount = 2;
    const double depositRate = 0.04;

    ProcessBonds(client, allBonds, yearsCount, depositRate, brokerTransactionFee);

    StopEventLoop();

    exit(0);
}

