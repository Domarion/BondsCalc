module moexparser;

public import apphelpers;
public import moexdata;

BondExt[] ParseBonds(string aJsonString)
{
    BondExt[] bonds;

    auto jsonObj = parseJSON(aJsonString);
    // У Moex данные складываются в массив из 2х элементов
    auto jsonObj1 = jsonObj.array[1];
    auto securities = jsonObj1["securities"].array;
    // В узле securities первым узлом идут метаданные, затем массив с данными
    auto securitiesData = securities[1].array;
    if (securitiesData.length > 0)
    {
        foreach (sec; securitiesData)
        {
            BondExt bond = GetObj!(BondExt, MoexGetter)(sec.object);
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
            
            bonds ~= bond;
        }
    }

    return bonds;
}

AmortCursor ParseAmortCursor(string aJsonString)
{
    auto jsonObj = parseJSON(aJsonString);
    // У Moex данные складываются в массив из 2х элементов
    auto jsonObj1 = jsonObj.array[1];
    auto cursor0 = jsonObj1["amortizations.cursor"].array[0];

    return GetObj!(AmortCursor, MoexGetter)(cursor0.object);
}

AmortData[] ParseAmortData(string aJsonString)
{
    AmortData[] amortsData;

    auto jsonObj = parseJSON(aJsonString);
    // У Moex данные складываются в массив из 2х элементов
    auto jsonObj1 = jsonObj.array[1];
    auto amortsJsonData = jsonObj1["amortizations"].array;
    // В узле securities первым узлом идут метаданные, затем массив с данными
    if (amortsJsonData.length > 0)
    {
        foreach (amortJson; amortsJsonData)
        {
            AmortData a = GetObj!(AmortData, MoexGetter)(amortJson.object);

            if (HasAmortizationData(a.data_source))
            {
                amortsData ~= a;
            }
        }
    }

    return amortsData;
}

SecurityDesc ParseSecurityDesc(const string aJsonString)
{
    auto jsonObj = parseJSON(aJsonString);
    // У Moex данные складываются в массив из 2х элементов
    auto jsonObj1 = jsonObj.array[1];
    auto descs = jsonObj1["description"].array;

    string[string] dict;
    foreach (jsonObjDesc; descs)
    {
        auto obj = jsonObjDesc.object;
        auto name = obj["name"].get!string;
        dict[name] = obj["value"].get!string;
    }

    return GetObj!SecurityDesc(dict);
}