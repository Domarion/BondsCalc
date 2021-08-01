module bondshelpers;

public import std.math;
import apphelpers;

long GetCouponPaidCount(
    const Date aBuyDate,
    const Date aTo,
    const Date aMaturityDate,
    const int aCouponPeriod)
{
    auto daysFromBuyDate = GetDaysBetweenDates(aMaturityDate, aBuyDate);
    auto daysFromToday = GetDaysBetweenDates(aMaturityDate, aTo);

    auto couponsFromBuyDate = cast(uint)daysFromBuyDate / cast(uint)aCouponPeriod;

    auto couponsFromToday = cast(uint)daysFromToday / cast(uint)aCouponPeriod;

    return couponsFromBuyDate - couponsFromToday;   
}

uint GetCouponCount(
    const Date aMaturityDate,
    const int aCouponPeriod,
    const Date aToday)
{
    auto daysDiff = GetDaysBetweenDates(aMaturityDate, aToday);
    return cast(uint)daysDiff / cast(uint)aCouponPeriod + 1;
}


/// Простая общая доходность до погашения с учётом налогов и сборов
/// Показывает доход без учёта реинвестирования и месячной платы брокеру
/// Учитывает налог на купоны и комиссию брокера за транзакцию.
double CalcCommonSimpleYield(
    const uint aCouponCount,
    const double aCouponSize,
    const double aFaceValue,
    const double aBondActualPrice,
    const double aBrokerTransactionFee,
    const double aAccruedInt)
{
    const double couponAmount = aCouponSize * aCouponCount;

    return CalcCommonSimpleYield(
        couponAmount,
        aFaceValue,
        aBondActualPrice,
        aBrokerTransactionFee,
        aAccruedInt);
}

double CalcCommonSimpleYield(
    const double aCouponsAmount,
    const double aFaceValue,
    const double aBondActualPrice,
    const double aBrokerTransactionFee,
    const double aAccruedInt)
{
    // Коэффициент при налоговой ставке 13%. Перенести в TaxInfo
    const double afterTax = 0.87;
    const double brokerTaxCoef = 1 + aBrokerTransactionFee;

    // Сумма купонов за весь срок с учётом налога 13%
    const double couponAmountWithTax = aCouponsAmount * afterTax;

    // Полная цена приобретения облигации
    const double allInCost = aBondActualPrice * brokerTaxCoef + aAccruedInt;
    
    // Доход с учётом разницы полной цены покупки облигации и номинала
    // writeln(couponAmountWithTax);
    // writeln(allInCost);
    // writeln(couponAmountWithTax/allInCost);

    const double absYield =  couponAmountWithTax + aFaceValue - allInCost;
    // writeln(absYield / allInCost);
    return quantize(absYield / allInCost, 0.0001);
}

unittest
{
    /// CalcCommonSimpleYield
    {
    const auto actual = CalcCommonSimpleYield(
        1,
        10,
        1000,
        1000,
        0,
        0
    );

    assert(approxEqual(actual, 0.0087));
    }

    {
        const auto actual = CalcCommonSimpleYield(
            10,
            10,
            1000,
            1000,
            0,
            0
        );

        assert(approxEqual(actual, 0.087));
    }

    {
        const auto actual = CalcCommonSimpleYield(
            10,
            10000,
            1000000,
            1000000,
            0,
            0
        );

        assert(approxEqual(actual, 0.087));
    }

    // Очень маленький купон, низкая цена облигации
    {
        const auto actual = CalcCommonSimpleYield(
            2,
            1000,
            750,
            0.05 * 0.01,
            0
        );

        assert(approxEqual(actual, 0.335));
    }

    // Нет купонов
    {
        const auto actual = CalcCommonSimpleYield(
            0,
            1000,
            750,
            0.05 * 0.01,
            0
        );

        assert(approxEqual(actual, 0.333));
    }
}


/// Простая годовая доходность до погашения с учётом налогов и сборов
double CalcSimpleYieldPerYear(
    const double aCommonSimpleYield,
    const Date aFrom,
    const Date aMaturityDate)
{
    const double dateDiff = GetDateDiffInYears(aFrom, aMaturityDate);
    if (approxEqual(dateDiff, 0.0))
    {
        return 0.0;
    }

    const double perYearYield = aCommonSimpleYield / dateDiff;

    return perYearYield.quantize!floor(0.001);
}

/// Среднегодовая простая доходность
unittest
{
    // Не общей доходности - нет среднегодовой
    {
        const auto today = Date(2021, 7, 16);
        const auto matDate = Date(2022, 6, 15);

        const auto actual = CalcSimpleYieldPerYear(
            0,
            today,
            matDate
        );

        assert(approxEqual(actual, 0.0));
    }
    // Нет cрока - нет доходности
    {
        const auto today = Date(2021, 7, 16);

        const auto actual = CalcSimpleYieldPerYear(
            0,
            today,
            today
        );

        assert(approxEqual(actual, 0.0));
    }

    // Нет cрока - нет доходности
    {
        const auto today = Date(2021, 7, 16);

        const auto actual = CalcSimpleYieldPerYear(
            0.1,
            today,
            today
        );

        assert(approxEqual(actual, 0.0));
    }

    // На сроке в 1 год = общей простой доходности
    {
        const auto today = Date(2021, 7, 16);
        const auto matdate = today + 365.days;

        const auto actual = CalcSimpleYieldPerYear(
            0.1,
            today,
            matdate
        );

        assert(approxEqual(actual, 0.1));
    }

    // На сроке в n лет = общей простой доходности/n
    {
        const auto today = Date(2021, 7, 16);
        const auto matdate = today + (365*2).days;

        const auto actual = CalcSimpleYieldPerYear(
            0.1,
            today,
            matdate
        );

        assert(approxEqual(actual, 0.05));
    }
}


unittest
{
    ///Расчёт числа купонов

    auto today = Date(2021, 7, 16);
    {
        const auto matDate = Date(2022, 6, 15);
        const int couponPeriod = 910;

        const auto actual = GetCouponCount(matDate, couponPeriod, today);
        assert(actual == 1);
    }

    {
        const auto matDate = Date(2021, 8, 17);
        const int couponPeriod = 31;

        const auto actual = GetCouponCount(matDate, couponPeriod, today);
        assert(actual == 2);
    }
}

unittest
{
    /// Число выплаченных мне купонов
    const auto buyDate = Date(2021,7,13);
    const auto tod = Date(2021,7,22);
    const auto matDate = Date(2022,12,20);
    const int couponPeriod = 192;

    const auto actual = GetCouponPaidCount(buyDate, tod, matDate, couponPeriod);
    assert(actual == 0);
}