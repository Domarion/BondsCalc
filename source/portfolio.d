module portfolio;

import std.csv;
import std.file : exists;
import std.algorithm;
import std.datetime;
import apphelpers;
import moexdata : IsEmptyDate;

struct Deal
{
    string ISIN;
    string Name;
    Date BuyDate = Date.min;
    double BuyPrice = 0.0;
    long Quantity;
    double AccruedIntQty = 0.0; // НКД за весь объем
    double CounterQuantity = 0.0; // Уплачено всего без учёта коммиссии
    double BrokerFee = 0.0; // Комиссия брокера в рублях
    bool HasAmortization = false; // Есть ли амортизация
    
    // Группа вычисляемых полей
    Date MaturityDate = Date.min;

    @("%") double SimpleYieldToMaturityPerYear = 0.0; // Простая годовая доходность в процентах от даты покупки до погашения
    @("%") double CommonSimpleYieldToMaturity = 0.0; // Простая общая доходность в процентах от даты покупки до погашения

    long CouponPaidCount; // Сколько купонов было выплачено
    double CouponValueInQty = 0.0; // Объем выплаченных купонов за вычетом налогов и НКД.
    double YieldIfSellToday = 0.0; // Доход в абсолютном значении, если продать облигации сегодня по прошлой VWAP цене (вычет всех расходов)
    double FaceValuePaid = 0.0; // Погашенная часть номинала за время владения
}

Deal[] ImportPortfolio(string aFileName)
{
    Deal[] deals;

    if (!aFileName.exists)
    {
        return deals;
    }

    auto file = File(aFileName, "r");

    foreach (record; csvReader!(string[string])
            (file.byLine.joiner("\n"), null, ';'))
    {
        deals ~= GetObj!(Deal, PortfolioGetter)(record);
    }

    file.close();

    foreach (deal; deals)
    {
        PrintObj!Deal(deal, stdout);
    }

    return deals;
}

void PortfolioGetter(TMember)(string aVal, ref TMember a)
{
    static if (is(TMember == Date))
    {
        if (!IsEmptyDate(aVal))
        {
            a = Date.fromISOExtString(aVal);
        }
        else
        {
            a = Date.min;
        }
    }
    else
    {
        SimpleGetter!TMember(aVal, a);
    }
}
