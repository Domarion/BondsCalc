module portfolio;

import std.csv;
import std.file : exists;
import std.algorithm;
import std.datetime;
import apphelpers;
import moexdata : IsEmptyDate;

enum Sides
{
    Buy = 0,
    Sell = 1
}

struct Deal
{
    string SECID;
    string ISIN;
    string Name;
    Sides Side;
    Date DealDate = Date.min;
    double Price = 0.0;
    long Quantity; // Число бумаг.
    double AccruedIntQty = 0.0; // НКД за весь объем
    double BrokerFee = 0.0; // Комиссия брокера в рублях
    bool HasAmortization = false; // Есть ли амортизация
    Date SellDate = Date.min;
    
    // Группа вычисляемых полей
    Date MaturityDate = Date.min;

    @("%") double SimpleYieldToMaturityPerYear = 0.0; // Простая годовая доходность в процентах от даты покупки до погашения
    @("%") double CommonSimpleYieldToMaturity = 0.0; // Простая общая доходность в процентах от даты покупки до погашения

    long CouponPaidCount; // Сколько купонов было выплачено
    double CouponValueInQty = 0.0; // Объем выплаченных купонов за вычетом налогов и НКД.
    double YieldIfSellToday = 0.0; // Доход в абсолютном значении, если продать облигации сегодня по прошлой VWAP цене (вычет всех расходов)
    double FaceValuePaid = 0.0; // Погашенная часть номинала за время владения для одной облигации
}

/// Информация об облигации на дату запроса.
struct BondInfo
{
    string Isin;
    string Name;
    int ListLevel = 0; // Уровень листинга на бирже(меньше - надежней)
    Date MaturityDate = Date.min;
    long Quantity = 0; // Общее число бумаг на дату запроса
    double VwapPrice = 0.0; // Средневзвешенная цена (расчёт по all-in price)
    @("%") double PortfolioPercentage = 0.0; // Процент от общего объема портфеля
    @("%") double LevelPercentage = 0.0; // Процент от облигаций этого уровня
}

struct Summary
{
    double SpentWithoutBrokerMontlyFee = 0.0; // Потрачено денег без брокерской месячной комиссии
    double Spent = 0.0; // Потрачено денег
    double BrokerMonthlyPaymentTotal = 0.0; // Всего уплачено брокеру(считаются только ежемесячные платежи)
    double BrokerTransactionTaxTotal = 0.0; // Транзакционные издержки(неявно учитывается в Spent)
    double ReceivedCouponAmount = 0.0; // Получено денег с купонов
    double ReceivedNominal = 0.0; // Выплачено из тела долга
    double ReceivedFromSell = 0.0; // Получено денег от продажи
    double Received = 0.0; // Получено денег всего
    @("%") double ReceivedToSpent = 0.0; // Процент полученных денег к потраченным
    double[3] ActiveSpentByLevels; // Процент активных (непогашенных, непроданных) облигаций в портфеле по уровням (ListLevel 1-3)
}

alias DealsByIsin = Deal[][string];

DealsByIsin ImportPortfolio(string aFileName)
{
    DealsByIsin deals;

    if (!aFileName.exists)
    {
        return deals;
    }

    auto file = File(aFileName, "r");

    foreach (record; csvReader!(string[string])
            (file.byLine.joiner("\n"), null, ';'))
    {
        auto deal = GetObj!(Deal, PortfolioGetter)(record);
        deals[deal.ISIN] ~= deal;

    }
    file.close();

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
