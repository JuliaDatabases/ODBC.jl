using Dates

# Julia mapping C structs
struct SQLDate <: Dates.AbstractTime
    year::Int16
    month::Int16
    day::Int16
end

Base.show(io::IO,x::SQLDate) = show(io, Date(x))
SQLDate(x::Dates.Date) = SQLDate(Dates.yearmonthday(x)...)
SQLDate() = SQLDate(0,0,0)
Base.zero(::Type{SQLDate}) = SQLDate()
import Base: ==
==(x::SQLDate, y::Dates.Date) = x.year == Dates.year(y) && x.month == Dates.month(y) && x.day == Dates.day(y)
==(y::Dates.Date, x::SQLDate) = x.year == Dates.year(y) && x.month == Dates.month(y) && x.day == Dates.day(y)
Dates.Date(x::SQLDate) = Date(Dates.UTD(Dates.totaldays(x.year, max(x.month, 1), x.day)))

struct SQLTime <: Dates.AbstractTime
    hour::Int16
    minute::Int16
    second::Int16
end

Base.show(io::IO,x::SQLTime) = show(io, Time(x))
SQLTime(x::Dates.Time) = SQLTime(Dates.hour(x), Dates.minute(x), Dates.second(x))
Dates.Time(x::SQLTime) = Time(Dates.Nanosecond(1000000000 * x.second + 60000000000 * x.minute + 3600000000000 * x.hour))
SQLTime() = SQLTime(0,0,0)
Base.zero(::Type{SQLTime}) = SQLTime()

struct SQLTimestamp <: Dates.AbstractTime
    year::Int16
    month::Int16
    day::Int16
    hour::Int16
    minute::Int16
    second::Int16
    fraction::Int32 #nanoseconds
end

Base.show(io::IO,x::SQLTimestamp) = show(io, DateTime(x))
function SQLTimestamp(x::Dates.DateTime)
    y, m, d = Dates.yearmonthday(x)
    h, mm, s = Dates.hour(x), Dates.minute(x), Dates.second(x)
    frac = Dates.millisecond(x) * 1_000_000
    return SQLTimestamp(y, m, d, h, mm, s, frac)
end
SQLTimestamp() = SQLTimestamp(0,0,0,0,0,0,0)
Base.zero(::Type{SQLTimestamp}) = SQLTimestamp()
==(x::SQLTimestamp, y::Dates.DateTime) = x.year == Dates.year(y) && x.month == Dates.month(y) && x.day == Dates.day(y) &&
                                   x.hour == Dates.hour(y) && x.minute == Dates.minute(y) && x.second == Dates.second(y)
==(y::Dates.DateTime, x::SQLTimestamp) = x.year == Dates.year(y) && x.month == Dates.month(y) && x.day == Dates.day(y) &&
                               x.hour == Dates.hour(y) && x.minute == Dates.minute(y) && x.second == Dates.second(y)
Dates.DateTime(x::SQLTimestamp) = DateTime(Dates.UTM((x.fraction ÷ 1_000_000) + 1000 * (x.second + 60 * x.minute + 3600 * x.hour + 86400 * Dates.totaldays(x.year, max(x.month, 1), x.day))))

struct SQL_SS_Time2 <: Dates.AbstractTime
    hour::Cushort;  #  SQLUSMALLINT hour;
    minute::Cushort; #  SQLUSMALLINT minute;
    second::Cushort; # SQLUSMALLINT second;
    fraction::Cuint; # SQLUINTEGER  fraction;
end

const SQL_MAX_NUMERIC_LEN = 16
struct SQLNumeric
    precision::SQLCHAR
    scale::SQLSCHAR
    sign::SQLCHAR
    val::NTuple{SQL_MAX_NUMERIC_LEN,SQLCHAR}
end

Base.show(io::IO,x::SQLNumeric) = print(io,"SQLNumeric($(x.sign == 1 ? '+' : '-') precision: $(x.precision) scale: $(x.scale) val: $(x.val))")
SQLNumeric() = SQLNumeric(0,0,0,(0,))


