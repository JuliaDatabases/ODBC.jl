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
function ODBCConnect!(dbc::Ptr{Void},dsn::String,username::String,password::String)
	if @FAILED SQLConnect(dbc,dsn,username,password)
		ODBCError(SQL_HANDLE_DBC,dbc)
		error("[ODBC]: SQLConnect failed; Return Code: $ret")
	end
end
#ODBCDriverConnect: Alternative connect function that allows user to create datasources on the fly through opening the ODBC admin
function ODBCDriverConnect!(dbc::Ptr{Void},conn_string::String,driver_prompt::Uint16)
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
function ODBCFetch(stmt::Ptr{Void},meta::Metadata,file::Output,delim::Union(Char,Array{Char,1}),result_number::Int)
	if (meta.rows != 0 && meta.cols != 0) #with catalog functions or all-filtering WHERE clauses, resultsets can have 0 rows/cols
		rowset = MULTIROWFETCH > meta.rows ? meta.rows : MULTIROWFETCH
		SQLSetStmtAttr(stmt,SQL_ATTR_ROW_ARRAY_SIZE,uint(rowset),SQL_IS_UINTEGER)
		# indicator = Array(Int32, (rowset,meta.cols))
		columns = ref(Any)
		julia_types = ref(DataType)
		#Main numeric types are mapped to appropriate Julia types; all others currently default to strings via Uint8 Arrays
		#Once Julia has a system for passing C structs, we can support native date, timestamp, and interval types
		#See the ODBC_Types.jl file for more information on type mapping
		for x in 1:meta.cols
			sqltype = meta.coltypes[x][2]
			ctype = get(SQL2C,sqltype,SQL_C_CHAR)
			jtype = get(SQL2Julia,sqltype,Uint8)
			holder = jtype == Uint8 ? Array(Uint8, (meta.colsizes[x]+1,rowset)) : Array(jtype, rowset)
			jlsize = jtype == Uint8 ? meta.colsizes[x]+1 : sizeof(jtype)
			push!(julia_types,jtype == Uint8 ? String : jtype)
			if @SUCCEEDED ODBC.SQLBindCols(stmt,x,ctype,holder,jlsize,C_NULL,jtype)
				push!(columns,holder)
			else #SQL_ERROR
				ODBCError(SQL_HANDLE_STMT,stmt)
				error("[ODBC]: SQLBindCol $x failed; Return Code: $ret")
			end
		end
		if file == :DataFrame
			if rowset < meta.rows #if we need multiple fetchscroll calls
				cols = ref(Any)
				for j = 1:meta.cols
					push!(cols,ref(julia_types[j]))
				end
				fetchseq = 1:rowset:meta.rows
				for i in fetchseq
					if @SUCCEEDED SQLFetchScroll(stmt,SQL_FETCH_NEXT,0)
						if i == last(fetchseq)
							colend = meta.rows - i + 1
						else
							colend = rowset
						end
						for j = 1:meta.cols
							if typeof(columns[j]) == Array{Uint8,2}
								append!(cols[j],nullstrip(columns[j][1:colend*(meta.colsizes[j]+1)],meta.colsizes[j]+1,colend))
							else
								append!(cols[j],deepcopy(columns[j][1:colend]))
							end	
						end
					else
						ODBCError(SQL_HANDLE_STMT,stmt)
						ODBCFreeStmt!(stmt)
						error("[ODBC]: Fetching results failed; Return Code: $ret")
					end
				end
				resultset = DataFrame(cols, Index(meta.colnames))
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
					ODBCFreeStmt!(stmt)
					error("[ODBC]: Fetching results failed; Return Code: $ret")
				end
			end
		elseif typeof(file) == Symbol
			error("[ODBC]: No result retrieval method is implemented for $file")
		else
			resultset = ODBCDirectToFile(stmt,meta,columns,file,delim,result_number)
		end
		return resultset
	else
		return DataFrame("No Rows Returned")
	end
end
function ODBCDirectToFile(stmt::Ptr{Void},meta::Metadata,columns::Array{Any,1},file::Output,delim::Union(Char,Array{Char,1}),result_number::Int)
	#TODO:
	#I think we're double writing some values on the last rowset fetch! Need to confirm though...
	#how to specify .csv .txt? allow delim in query()?
	rowset = MULTIROWFETCH > meta.rows ? meta.rows : MULTIROWFETCH
	if typeof(file) <: String #If there's just one filename given
		outer = file
	else
		outer = file[result_number+1]
	end
	if typeof(delim) == Char
		delim = delim
	else
		delim = delim[result_number+1]
	end
	out_file = open(outer,"w")
	write(out_file,join(meta.colnames,delim)*"\n")

	fetchseq = 1:rowset:meta.rows
	for i in fetchseq
		if @SUCCEEDED SQLFetchScroll(stmt,SQL_FETCH_NEXT,0)
			for k = 1:rowset, j = 1:meta.cols
				if j < meta.cols
					if typeof(columns[j]) == Array{Uint8,2}	
		        		write(out_file,escape_string(nullstrip(columns[j][:,k])))
		        		write(out_file,delim)
		        	else
						write(out_file,string(columns[j][k]))
						write(out_file,delim)
		        	end
		      	else
		      		if typeof(columns[j]) == Array{Uint8,2}	
		        		write(out_file,escape_string(nullstrip(columns[j][:,k])))
		        		write(out_file,"\n")
		        	else
						write(out_file,string(columns[j][k]))
						write(out_file,"\n")
		        	end
		      	end			
			end
		else
			ODBCError(SQL_HANDLE_STMT,stmt)
			ODBCFreeStmt!(stmt)
			error("[ODBC]: Fetching results failed; Return Code: $ret")
		end
	end
	close(out_file)
	resultset = DataFrame("Results saved to $outer")
	return resultset
end
#ODBCFreeStmt!: used to 'clear' a statement of bound columns, resultsets, and other bound parameters in preparation for a subsequent query
function ODBCFreeStmt!(stmt)
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
function nullstrip(stringblob, colsize::Int, rowset::Int)
	a = Array(String,rowset)
	n = 1
	for i in 1:colsize:length(stringblob)
		a[n] = nullstrip(stringblob[i:i+colsize-1])
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
