
type Sink <: Data.Sink
    schema::Data.Schema
    dsn::DSN
    table::String
end

# insert into existing table
# function Sink(dsn, schema::Data.Schema, table::String)
#
# end

# DataStreams Sink interface
Data.streamtypes{T<:ODBC.Sink}(::Type{T}) = [Data.Column]

function Data.stream!(source, ::Type{Data.Column}, sink::ODBC.Sink)
    Data.types(source) == Data.types(sink) || throw(ArgumentError("schema mismatch: \n$(Data.schema(source))\nvs.\n$(Data.schema(sink))"))
    rows, cols = size(source)
    Data.isdone(source, 1, 1) && return sink
    ODBC.execute!(sink.dsn, "select * from $(sink.table)")
    stmt = sink.dsn.stmt_ptr
    ODBC.API.SQLSetStmtAttr(stmt, ODBC.API.SQL_ATTR_ROW_ARRAY_SIZE, rows, ODBC.API.SQL_IS_UINTEGER)
    types = Data.types(source)
    indcols = Array{Vector{ODBC.API.SQLLEN}}(cols)
    row = 0
    while !Data.isdone(source, row+1, cols+1)
        for col = 1:cols
            T = types[col]
            cT = ODBC.API.julia2C[T]
            column = Data.getcolumn(source, T, col)
            ind = Array{ODBC.API.SQLLEN}(rows)
            indcols[col] = ind
            ODBC.API.SQLBindCols(stmt, col, cT, pointer(column.values), sizeof(eltype(column.values)), ind)
        end
        ODBC.API.SQLBulkOperations(stmt, ODBC.API.SQL_ADD)
    end
    Data.setrows!(source, row)
    return sink
end

function load(dsn, table::String, source)
    sink = ODBC.Sink(Data.schema(source), dsn, table)
    return Data.stream!(source, sink)
end
