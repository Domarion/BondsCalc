module moexparser;

public import apphelpers;
public import moexdata;

Bond[] ParseBonds(string aJsonString)
{
    Bond[] bonds;

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
            Bond b = GetObj!Bond(sec);

            bonds ~= b;
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

    return GetObj!AmortCursor(cursor0);
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
            AmortData a = GetObj!AmortData(amortJson);

            if (HasAmortizationData(a.data_source))
            {
                amortsData ~= a;
            }
        }
    }

    return amortsData;
}
