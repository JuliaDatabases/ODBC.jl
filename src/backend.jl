function ODBCAllocHandle(handletype,parenthandle)
	handle = Array(Ptr{Void},1)
	if @FAILED SQLAllocHandle(handletype,parenthandle,handle)
		error("[ODBC]: ODBC Handle Allocation Failed; Return Code: $ret")
	else		
		#If allocation succeeded, retrieve handle pointer stored in handle's array index 1
		handle = handle[1]
		if handletype == SQL_HANDLE_ENV 
			if @FAILED SQLSetEnvAttr(handle,SQL_ATTR_ODBC_VERSION,SQL_OV_ODBC3)
				#If version-setting fails, release environment handle and set global env variable to a null pointer
				SQLFreeHandle(SQL_HANDLE_ENV,handle)
				global env = C_NULL
				error("[ODBC]: Failed to set ODBC version; Return Code: $ret")
			end
		end
	end
	return handle
end
#ODBCConnect: Connect to qualified DSN (pre-established through ODBC Admin), with optional username and password inputs
function ODBCConnect(dbc::Ptr{Void},dsn::String,username,password)
	if @FAILED SQLConnect(dbc,dsn,username,password)
		ODBCError(SQL_HANDLE_DBC,dbc)
		error("[ODBC]: SQLConnect failed; Return Code: $ret")
	end
end
ls
#ODBCDriverConnect: Alternative connect function that allows user to create datasources on the fly through opening the ODBC admin
function ODBCDriverConnect(dbc::Ptr{Void},conn_string::String,driver_prompt::Uint16)
	window_handle = C_NULL	
	@windows_only window_handle = ccall( (:GetForegroundWindow, "user32"), Ptr{Void}, () )
		
	if @FAILED SQLDriverConnect(dbc,window_handle,conn_string,ref(Uint8),ref(Int16),driver_prompt)
		ODBCError(SQL_HANDLE_DBC,dbc)
		error("[ODBC]: SQLDriverConnect failed; Return Code: $ret")
	end
end
#ODBCQueryExecute: Send query to DMBS
function ODBCQueryExecute(stmt::Ptr{Void},querystring::String)
	if @FAILED SQLExecDirect(stmt,querystring)
		ODBCError(SQL_HANDLE_STMT,stmt)
		error("[ODBC]: SQLExecDirect failed; Return Code: $ret")
	end
end
#ODBCMetadata: Retrieve resultset metadata once query is processed, Metadata type is returned
function ODBCMetadata(stmt::Ptr{Void},querystring::String)
		#Allocate space for and fetch number of columns and rows in resultset
		cols = Array(Int16,1)
		rows = Array(Int,1)
		SQLNumResultCols(stmt,cols)
		SQLRowCount(stmt,rows)
		#Allocate arrays to hold each column's metadata
		colnames = ref(ASCIIString)
		coltypes = Array((String,Int16),0)
		colsizes = ref(Int)
		coldigits = ref(Int16)
		colnulls = ref(Int16)
		#Allocate space for and fetch the name, type, size, etc. for each column
		for x in 1:cols[1]
			column_name = Array(Uint8,256)
			name_length = Array(Int16,1)
			datatype = Array(Int16,1)
			column_size = Array(Int,1)
			decimal_digits = Array(Int16,1)
			nullable = Array(Int16,1) 
			SQLDescribeCol(stmt,x,column_name,name_length,datatype,column_size,decimal_digits,nullable)
			push!(colnames,nullstrip(column_name))
			push!(coltypes,(get(SQL_TYPES,int(datatype[1]),"SQL_CHAR"),datatype[1]))
			push!(colsizes,int(column_size[1]))
			push!(coldigits,decimal_digits[1])
			push!(colnulls,nullable[1])
		end
	return Metadata(querystring,int(cols[1]),rows[1],colnames,coltypes,colsizes,coldigits,colnulls)
end
#ODBCFetch: Using resultset metadata, allocate space/arrays for previously generated resultset, retrieve results
function ODBCFetch(stmt::Ptr{Void},meta::Metadata,output::Union(String,Array{String,1}),delimiter::Union(Char,Array{Char,1}),result_number::Int)
	if (meta.rows != 0 && meta.cols != 0) #with catalog functions or all-filtering WHERE clauses, resultsets can have 0 rows/cols
		rowset = MULTIROWFETCH > meta.rows ? meta.rows : MULTIROWFETCH
		SQLSetStmtAttr(stmt,SQL_ATTR_ROW_ARRAY_SIZE,uint(rowset),SQL_IS_UINTEGER)
		indicator = Array(Int, (rowset,meta.cols))
		columns = ref(Any)
		julia_types = ref(Any)
		#Main numeric types are mapped to appropriate Julia types; all others currently default to strings via Uint8 Arrays
		#Once Julia has a system for passing C structs, we can support native date and timestamp types
		#See the 'consts.jl' file for more information
		for x in 1:meta.cols
			type_value = meta.coltypes[x][2]
			if contains((SQL_BIT,SQL_TINYINT),type_value)
				ctype = SQL_C_TINYINT
				juliatype = Int8
			elseif type_value == SQL_SMALLINT
				ctype = SQL_C_SHORT
				juliatype = Int16
			elseif contains((SQL_INTEGER),type_value)
				ctype = SQL_C_LONG
				juliatype = Int
			elseif type_value == SQL_BIGINT
				ctype = SQL_C_BIGINT
				juliatype = Int64
			elseif contains((SQL_REAL,SQL_DECIMAL,SQL_NUMERIC,SQL_FLOAT,SQL_DOUBLE),type_value)
				ctype = SQL_C_DOUBLE
				juliatype = Float64
			else
				ctype = SQL_C_CHAR
				juliatype = Uint8
			end
			holder = juliatype == Uint8 ? Array(Uint8, (meta.colsizes[x]+1,rowset)) : Array(juliatype, rowset)
			jlsize = juliatype == Uint8 ? meta.colsizes[x]+1 : sizeof(juliatype)
			push!(julia_types,juliatype == Uint8 ? String : juliatype)
			if @SUCCEEDED ODBC.SQLBindCols(stmt,x,ctype,holder,jlsize,indicator,juliatype)
				push!(columns,holder)
			else #SQL_ERROR
				ODBCError(SQL_HANDLE_STMT,stmt)
				error("[ODBC]: SQLBindCol $x failed; Return Code: $ret")
			end
		end
		if !ismatch(r"dataframe"i,output)
			resultset = ODBCDirectToFile(stmt,meta,columns,output,delimiter,result_number)
		else	
			if rowset < meta.rows #if we need multiple fetchscroll calls
				resultset = ODBCLargeFetch(stmt,meta,columns,julia_types)
			else #if we only need one fetchscroll call
				if @SUCCEEDED SQLFetchScroll(stmt,SQL_FETCH_NEXT,0)
					for j = 1:meta.cols
						if typeof(columns[j]) == Array{Uint8,2}
							columns[j] = DataArray(nullstrip(columns[j],meta.colsizes[j]+1,meta.rows))
						end	
					end
					resultset = DataFrame(columns, Index(meta.colnames))
				else
					ODBCError(SQL_HANDLE_STMT,stmt)
					ODBCFreeStmt(stmt)
					error("[ODBC]: Fetching results failed; Return Code: $ret")
				end
			end
		end
		return resultset
	else
		return DataFrame("No Rows Returned")
	end
end
function ODBCLargeFetch(stmt::Ptr{Void},meta::Metadata,columns::Array{Any,1},julia_types::Array{Any,1})
	rowset = MULTIROWFETCH > meta.rows ? meta.rows : MULTIROWFETCH
	cols = Array(Any,length(columns))
	for i = 1:length(columns)
		cols[i] = DataArray(julia_types[i],meta.rows)
		for j in 1:meta.rows
		    cols[i][j] = DataFrames.baseval(julia_types[i])
            cols[i][j] = NA
		end
	end
	resultset = DataFrame(cols, Index(meta.colnames))
	fetchseq = 1:rowset:meta.rows
	for i in fetchseq
		if @SUCCEEDED SQLFetchScroll(stmt,SQL_FETCH_NEXT,0)
			if i == last(fetchseq)
				dfend = meta.rows
				colend = meta.rows - i + 1
			else
				dfend = i+rowset-1		
				colend = rowset
			end
			for j = 1:length(columns)
				if typeof(columns[j]) == Array{Uint8,2}
					resultset[i:dfend,j] = nullstrip(copy(columns[j][1:colend*(meta.colsizes[j]+1)]),meta.colsizes[j]+1,colend)
				else
					resultset[i:dfend,j] = copy(columns[j][1:colend])
				end	
			end
		else
			ODBCError(SQL_HANDLE_STMT,stmt)
			ODBCFreeStmt(stmt)
			error("[ODBC]: Fetching results failed; Return Code: $ret")
		end
	end
	return resultset
end
function ODBCDirectToFile(stmt::Ptr{Void},meta::Metadata,columns::Array{Any,1},output::Union(String,Array{String,1}),delimiter::Union(Char,Array{Char,1}),result_number::Int)
	#TODO:
	#need to just straight copy columns as dataarrays then print_table on combined dataframe with each loop, with header = TRUE on first loop
	#how to specify .csv .txt? allow delimiter in query()?
	rowset = MULTIROWFETCH > meta.rows ? meta.rows : MULTIROWFETCH
	if typeof(output) == ASCIIString #If there's just one filename given
		outer = output
	else
		outer = output[result_number+1]
	end
	if typeof(delimiter) == Char
		delim = delimiter
	else
		delim = delimiter[result_number+1]
	end
	out_file = open(outer,"a")
	holder = DataFrame(rowset,meta.cols)
	names!(holder.colindex,meta.colnames)
	fetchseq = 1:rowset:meta.rows
	for i in fetchseq
		if @SUCCEEDED SQLFetchScroll(stmt,SQL_FETCH_NEXT,0)
			for j = 1:length(columns)
				if typeof(columns[j]) == Array{Uint8,2}
					holder[j] = nullstrip(copy(columns[j][1:rowset*(meta.colsizes[j]+1)]),meta.colsizes[j]+1,rowset)
				else
					holder[j] = copy(columns[j][1:rowset])
				end	
			end
		else
			ODBCError(SQL_HANDLE_STMT,stmt)
			ODBCFreeStmt(stmt)
			error("[ODBC]: Fetching results failed; Return Code: $ret")
		end
		if i == fetchseq.start
			print_table(out_file,holder,delim,'"',true)
			print("Retrieving $(meta.rows) rows: ")
		else
			print_table(out_file,holder,delim,'"',false)
			print(round(i/meta.rows,2))
		end
	end
	close(out_file)
	resultset = DataFrame("Results saved to $output")
	return resultset
end
#ODBCFreeStmt: used to 'clear' a statement of bound columns, resultsets, and other bound parameters in preparation for a subsequent query
function ODBCFreeStmt(stmt)
	SQLFreeStmt(stmt,SQL_CLOSE)
	SQLFreeStmt(stmt,SQL_UNBIND)
	SQLFreeStmt(stmt,SQL_RESET_PARAMS)
end
#String Helper Function: String buffers are allocated for 256 characters, after data is fetched,
#this function strips out all the unused buffer space and converts Array{Uint8} to Julia string
function nullstrip(string::Array{Uint8})
	if ndims(string) > 1
		string = string[1:end]
	end
	bytes = search(bytestring(string),"\0")[1] - 1
	bytestring(string[1:bytes])
end
function nullstrip(stringblob, colsize::Real, rowset::Real)
	a = DataArray(String,rowset)
	n = 1
	for i in 1:colsize:length(stringblob)
		a[n] = nullstrip(stringblob[i:i+colsize-1])
		if a[n] == "" a[n] = NA end
		n+=1
	end
	return a
end
#Error Reporting: Takes an SQL handle as input and retrieves any error messages associated with that handle; there may be more than one
function ODBCError(handletype::Int16,handle::Ptr{Void})
	i = int16(1)
	state = Array(Uint8,6)
	error_msg = Array(Uint8, 1024)
	native = Array(Int,1)
	msg_length = Array(Int16,1)
	while @SUCCEEDED SQLGetDiagRec(handletype,handle,i,state,native,error_msg,msg_length)
		st = nullstrip(state)
		msg = nullstrip(error_msg)
		println("[ODBC] $st: $msg")
		i = int16(i+1)
	end
end
