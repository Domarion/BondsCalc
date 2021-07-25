module apphelpers;

public import std.json;
public import std.format;
public import std.stdio;
public import std.conv : to;
public import std.datetime;
import std.math;

bool empty(Date aDate)
{
    return aDate == Date.min;
}

void SimpleGetter(TMember)(JSONValue aVal, ref TMember a)
{
    if (!aVal.isNull)
    {
        a = aVal.get!TMember;
    }
}

void SimpleGetter(TMember)(string aVal, ref TMember a)
{
    if (aVal.length > 0)
    {
        static if (is(TMember == bool))
        {
            a = cast(bool) to!int(aVal);
        }
        else
        {
            a = to!TMember(aVal);
        }
    }
}

// TODO: Научиться передавать Getter
TStruct GetObj(TStruct, alias getter = SimpleGetter, TDict)(TDict[string] aDict)
{
    import std.traits : FieldNameTuple;
    import std.meta : Alias;

    TStruct structObj;

    foreach (fieldName; FieldNameTuple!TStruct)
    {
        if (fieldName in aDict)
        {
            alias membertype = typeof(__traits(getMember, structObj, fieldName));
            getter!membertype(aDict[fieldName], __traits(getMember, structObj, fieldName));
        }
    }

    return structObj;
}

string GetValue(T)(const T aObj)
{
    import std.traits : Unqual;

    static if (is (Unqual!(T) == Date))
    {
        if (!empty(aObj))
        {
            return aObj.toISOExtString();
        }
        else
        {
            return "none";
        }
    }
    else static if (is (Unqual!(T) == double))
    {
        import std.string : tr;
        return tr(format("%g", aObj), ",", ".");
    }
    else
    {
        return to!string(aObj);
    }
}

string[string] GetOneAttributeForFields(TStruct)()
{
    string[string] attributes;

    import std.traits : FieldNameTuple;
    alias fieldList = FieldNameTuple!TStruct;

    foreach(field; fieldList)
    {
        alias attribList = __traits(getAttributes, mixin("TStruct."~field));
        static if(attribList.length > 0)
        {
            attributes[field] = attribList[0];
        }
    }

    return attributes;
}

void PrintObj(TStruct)(const TStruct aObj, File aStream)
{
    import std.traits : FieldNameTuple;

    auto fieldList = FieldNameTuple!TStruct;

    auto values = aObj.tupleof;
    aStream.writeln(format("\n***%s***\n", TStruct.stringof));

    auto attributes = GetOneAttributeForFields!TStruct();
    foreach (index, value; values)
    {
        string val = GetValue(value);
        aStream.write(format("%-15s %s", fieldList[index], val));
        if (fieldList[index] in attributes)
        {
            aStream.write(attributes[fieldList[index]]);
        }
        aStream.write("\n");
    }
}

void PrintObjs(TStruct)(const TStruct[] aObjs, File aStream)
{
    foreach(const data; aObjs)
    {
        PrintObj(data, aStream);
    }
}

void PrintObjectsToFile(T)(const T[] aObjs, string aFileName)
{
    File file = File(aFileName, "w");
    PrintObjs(aObjs, file);
    file.close();
}

Date GetToday()
{
    return cast(Date)Clock.currTime();
}

Date GetPrevDay(const Date aDate)
{
    return aDate - 1.days;
}

long GetDaysBetweenDates(Date aFirst, Date aSecond)
{
    return abs(aSecond - aFirst).total!"days";
}

double GetDateDiffInYears(const Date aFirst, const Date aSecond)
{
    const double daysInYear = 365.0;
    // TODO: Правильно расчитать число дней между датами
    const auto daysDiff = GetDaysBetweenDates(aFirst, aSecond);

    // минимально округляем до разницы в 1 день.
    return quantize!floor(daysDiff / daysInYear, 0.001);
}

unittest
{
    ///Расчёт числа дней между текущей датой и датой погашения

    auto today = Date(2021, 7, 16);

    {
        const auto actual = GetDaysBetweenDates(Date(2021, 7, 16), today);
        assert(actual == 0);
    }

    {
        const auto actual = GetDaysBetweenDates(Date(2021, 7, 17), today);
        assert(actual == 1);
    }
    {
        const auto actual = GetDaysBetweenDates(today, Date(2021, 7, 17));
        assert(actual == 1);
    }

    {
        const auto actual = GetDaysBetweenDates(Date(2021, 8, 16), today);
        assert(actual == 31);
    }
}

unittest
{
    ///Расчёт дробного числа лет между датами

    auto today = Date(2021, 7, 16);

    {
        const auto actual = GetDateDiffInYears(Date(2021, 7, 16), today);
        assert(actual == 0);
    }

    {
        const auto actual = GetDateDiffInYears(Date(2021, 7, 17), today);
        assert(actual == 0.002);
    }
    {
        const auto actual = GetDateDiffInYears(today, Date(2021, 7, 17));
        assert(actual == 0.002);
    }

    {
        const auto actual = GetDateDiffInYears(Date(2021, 8, 16), today);
        assert(actual == 0.084);
    }

    {
        const auto actual = GetDateDiffInYears(Date(2022, 7, 16), today);
        assert(actual == 1);
    }

    {
        const auto actual = GetDateDiffInYears(Date(2023, 7, 16), today);
        assert(actual == 2);
    }
}
