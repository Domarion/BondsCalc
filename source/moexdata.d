module moexdata;

public import std.datetime;

struct Bond
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
}

struct BondExtension
{
    Bond TheBond;
    double YieldToMaturity = 0.0;
    bool HasAmortization = false;
}

struct AmortCursor
{
    long INDEX;
    long TOTAL;
    long PAGESIZE;
}

struct AmortData
{
 // Пока не учитываю амортизацию - интересно только её наличие
    string isin;
    string name;
//     double issuevalue = 0.0;
//     string amortdate;
//     double facevalue = 0.0;
//     double initialfacevalue = 0.0;
    string faceunit;
//     double valueprc= 0.0;
//     double value= 0.0;
//     double value_rub= 0.0;
    string data_source;
}

bool IsRub(string aCurrency)
{
    return aCurrency == "RUB"
        || aCurrency == "SUR";
}

bool IsAllowedBoard(string aBoard)
{
    // TQCB Т+ Облигации
    // TQOB Т+ Гособлигации

    return aBoard == "TQCB" || aBoard == "TQOB";
}

bool HasAmortizationData(string aDataSource)
{
    return aDataSource == "amortization";
}

