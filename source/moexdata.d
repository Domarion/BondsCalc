module moexdata;

import std.datetime;
import std.math;
import std.json;

struct BondExt
{
// Описание полей здесь: https://iss.moex.com/iss/engines/stock/markets/bonds/
    string SECID; // Идентификатор финансового инструмента
    string BOARDID; // Идентификатор режима торгов
    string SHORTNAME; // Краткое наименование ценной бумаги
    double PREVWAPRICE; // Средневзвешенная цена предыдущего дня, % к номиналу
    double COUPONVALUE = 0.0; // Сумма купона, в валюте номинала
    Date NEXTCOUPON = Date.min; // Дата окончания купона
    double ACCRUEDINT = 0.0; // НКД на дату расчетов, в валюте расчетов
    double PREVPRICE; // Цена последней сделки пред. дня, % к номиналу
    int LOTSIZE; // Размер лота, ц.б.
    double FACEVALUE = 0.0; // Непогашенный долг. Может быть меньше номинала из-за амортизации
    string BOARDNAME; // Режим торгов
    string STATUS;
    Date MATDATE = Date.min; // Дата погашения, дд.мм.гг
    int DECIMALS; // Точность, знаков после запятой
    int COUPONPERIOD; // Длительность купона
    long ISSUESIZE; // Объем выпуска, штук
    string SECNAME; // Наименование финансового инструмента
    string REMARKS; // Примечание
    double MINSTEP = 0.0; // Мин. шаг цены
    string FACEUNIT; // Валюта номинала
    double BUYBACKPRICE; // Цена оферты
    Date BUYBACKDATE = Date.min; // Дата, к которой рассчитывается доходность (если данное поле не заполнено, то "Доходность посл.сделки" рассчитывается к Дате погашения)
    string ISIN; // Какой-то код
    string CURRENCYID; // Сопр. валюта инструмента
    long ISSUESIZEPLACED; // Количество ценных бумаг в обращении
    int LISTLEVEL; // Уровень листинга
    string SECTYPE; // Тип ценной бумаги
    double COUPONPERCENT = 0.0; // Ставка купона, %
    Date OFFERDATE = Date.min; // Дата Оферты
    Date SETTLEDATE = Date.min; // Дата расчётов сделки(особо не интересна)
    double LOTVALUE = 0.0; // Номинальная стоимость лота, в валюте номинала

    // Небиржевые поля:
    @("% Общая простая доходность") double CommonSimpleYieldToMaturity = 0.0; // Общая простая доходность к дате погашения облигации
    @("% Годовая простая доходность") double SimpleYieldToMaturityPerYear = 0.0; // Годовая простая доходность к дате погашения облигации
    bool HasAmortization = false;
    // Cм. SecurityDesc
    bool ISQUALIFIEDINVESTORS = false;
    bool EARLYREPAYMENT = false;
}

// Можно использовать и для купонов
struct MoexCursor
{
    long INDEX;
    long TOTAL;
    long PAGESIZE;
}

struct AmortData
{
    string isin;
    string name;
//     double issuevalue = 0.0;
    Date amortdate; // дата амортизации (зависит от from и till)
    double facevalue = 0.0; // Актуальный размер номинала
    double initialfacevalue = 0.0; // Изначальный размер номинала
    // string faceunit;
//     double valueprc = 0.0;
//     double value= 0.0;
    double value_rub = 0.0; // размер амортизации (зависит от from и till)
    string data_source;
}

struct CouponData
{
    string isin;
    string name;
    Date coupondate; // Дата выплаты купона.
    // Date recorddate; // Непонятно какая дата
//     double valueprc = 0.0;
//     double value= 0.0;
    double value_rub = 0.0; // размер купона (зависит от from и till)
}

struct SecurityDesc
{
    string SECID;
    string ISIN;
    bool ISQUALIFIEDINVESTORS = false; // Бумаги для квалифицированных инвесторов
    bool EARLYREPAYMENT = false; // Возможен досрочный выкуп
}

bool IsRub(const string aCurrency)
{
    return aCurrency == "RUB"
        || aCurrency == "SUR";
}

bool IsAllowedBoard(const string aBoard)
{
    // TQCB Т+ Облигации
    // TQOB Т+ Гособлигации

    return aBoard == "TQCB" || aBoard == "TQOB";
}

bool HasAmortizationData(const string aDataSource)
{
    return aDataSource == "amortization";
}

bool IsValidPrice(const double aPrice)
{
    return !isNaN(aPrice) && aPrice != 0.0;
}

/// Получение актуальной цены облигации
/// Решил, что сначала нужно брать VWAP цену. Если её нет брать максимальную из предыдущей цены и номинала, иначе брать номинал.
double GetBondActualPrice(const BondExt aBond)
{
    if (IsValidPrice(aBond.PREVWAPRICE))
    {
        const double prevVwapPriceAbsolute = quantize!ceil(aBond.FACEVALUE * aBond.PREVWAPRICE / 100, aBond.MINSTEP);

        return prevVwapPriceAbsolute;
    }

    if (IsValidPrice(aBond.PREVPRICE))
    {
        // Предыдущая цена задаётся в процентах от номинала, поэтому делю на 100
        const double prevPriceAbsolute = quantize!ceil(aBond.FACEVALUE * aBond.PREVPRICE / 100, aBond.MINSTEP);
        return fmax(aBond.FACEVALUE, prevPriceAbsolute);
    }

    return aBond.FACEVALUE;
}

bool IsEmptyDate(const string aDate)
{
    return aDate.length == 0
        || aDate == "0000-00-00";
}

void MoexGetter(TMember)(JSONValue aVal, ref TMember a)
{
    if (!aVal.isNull)
    {
        static if (is(TMember == Date))
        {
            string dateISOExt = aVal.get!string;
            if (!IsEmptyDate(dateISOExt))
            {
                a = Date.fromISOExtString(dateISOExt);
            }
            else
            {
                a = Date.min;
            }
        }
        else
        {
            a = aVal.get!TMember;
        }
    }
}

