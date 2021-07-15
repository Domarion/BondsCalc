module apphelpers;

public import std.json;
public import std.format;
public import std.stdio;
public import std.conv : to;

import std.datetime;
import std.math : isNaN;

bool empty(Date aDate)
{
    return aDate == Date.min;
}

private bool IsEmptyDate(string aDate)
{
    return aDate.length == 0
        || aDate == "0000-00-00";
}

TStruct GetObj(TStruct)(JSONValue aJsonObj)
{
    import std.traits : FieldNameTuple;
    import std.meta : Alias;

    TStruct structObj;

    auto jsonObj = aJsonObj.object();
    foreach (fieldName; FieldNameTuple!TStruct)
    {
        alias membertype = typeof(__traits(getMember, structObj, fieldName));

        if (fieldName in jsonObj)
        {
            auto val = jsonObj[fieldName];
            if (!val.isNull)
            {
                static if (is(membertype == Date))
                {
                    string dateISOExt = val.get!string;
                    if (!IsEmptyDate(dateISOExt))
                    {
                        __traits(getMember, structObj, fieldName) = Date.fromISOExtString(dateISOExt);
                    }
                    else
                    {
                        __traits(getMember, structObj, fieldName) = Date.min;
                    }
                }
                else
                {
                    __traits(getMember, structObj, fieldName) = val.get!membertype;
                }
            }
        }
    }

    return structObj;
}

string GetValue(T)(T aObj)
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

void PrintObj(TStruct)(const TStruct aObj, File aStream)
{
    auto fieldList = [ __traits(allMembers, TStruct) ];

    auto values = aObj.tupleof;
    aStream.writeln(format("\n***%s***", TStruct.stringof));

    foreach (index, value; values)
    {
        string val = GetValue(value);
        aStream.writeln(format("%-15s %s", fieldList[index], val));
    }
}

void PrintObjectsToFile(T)(const T[] aObjs, string aFileName)
{
    File file = File(aFileName, "w");
    foreach(data; aObjs)
    {
        PrintObj(data, file);
    }
    file.close();
}

bool IsValidPrice(double aPrice)
{
    return !isNaN(aPrice) && aPrice != 0.0;
}

long GetDaysBetweenDates(Date aFirst, Date aSecond)
{
    return abs(aSecond - aFirst).total!"days";
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
