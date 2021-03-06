%{
/*-------------------------------------------------------------------------
 *
 * repl_scanner.l
 *	  a lexical scanner for the replication commands
 *
 * Portions Copyright (c) 1996-2011, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 *
 * IDENTIFICATION
 *	  src/backend/replication/repl_scanner.l
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

/* Avoid exit() on fatal scanner errors (a bit ugly -- see yy_fatal_error) */
#undef fprintf
#define fprintf(file, fmt, msg)  ereport(ERROR, (errmsg_internal("%s", msg)))

/* Handle to the buffer that the lexer uses internally */
static YY_BUFFER_STATE scanbufhandle;

static StringInfoData litbuf;

static void startlit(void);
static char *litbufdup(void);
static void addlit(char *ytext, int yleng);
static void addlitchar(unsigned char ychar);

%}

%option 8bit
%option never-interactive
%option nodefault
%option noinput
%option nounput
%option noyywrap
%option warn
%option prefix="replication_yy"

%x xq

/* Extended quote
 * xqdouble implements embedded quote, ''''
 */
xqstart			{quote}
xqdouble		{quote}{quote}
xqinside		[^']+

hexdigit		[0-9A-Za-z]+

quote			'
quotestop		{quote}

%%

BASE_BACKUP			{ return K_BASE_BACKUP; }
FAST			{ return K_FAST; }
IDENTIFY_SYSTEM		{ return K_IDENTIFY_SYSTEM; }
LABEL			{ return K_LABEL; }
NOWAIT			{ return K_NOWAIT; }
PROGRESS			{ return K_PROGRESS; }
WAL			{ return K_WAL; }
START_REPLICATION	{ return K_START_REPLICATION; }
","				{ return ','; }
";"				{ return ';'; }

[\n]			;
[\t]			;
" "				;

{hexdigit}+\/{hexdigit}+		{
					if (sscanf(yytext, "%X/%X", &yylval.recptr.xlogid, &yylval.recptr.xrecoff) != 2)
						yyerror("invalid streaming start location");
					return RECPTR;
				}

{xqstart}		{
					BEGIN(xq);
					startlit();
				}
<xq>{quotestop}	{
					yyless(1);
					BEGIN(INITIAL);
					yylval.str = litbufdup();
					return SCONST;
				}
<xq>{xqdouble} {
					addlitchar('\'');
				}
<xq>{xqinside}  {
					addlit(yytext, yyleng);
				}

<xq><<EOF>>		{ yyerror("unterminated quoted string"); }


<<EOF>>			{
					yyterminate();
				}

.				{
					ereport(ERROR,
							(errcode(ERRCODE_SYNTAX_ERROR),
							 errmsg("syntax error: unexpected character \"%s\"", yytext)));
				}
%%


static void
startlit(void)
{
	initStringInfo(&litbuf);
}

static char *
litbufdup(void)
{
	return litbuf.data;
}

static void
addlit(char *ytext, int yleng)
{
	appendBinaryStringInfo(&litbuf, ytext, yleng);
}

static void
addlitchar(unsigned char ychar)
{
	appendStringInfoChar(&litbuf, ychar);
}

void
yyerror(const char *message)
{
	ereport(ERROR,
			(errcode(ERRCODE_SYNTAX_ERROR),
			 errmsg_internal("%s", message)));
}


void
replication_scanner_init(const char *str)
{
	Size		slen = strlen(str);
	char	   *scanbuf;

	/*
	 * Might be left over after ereport()
	 */
	if (YY_CURRENT_BUFFER)
		yy_delete_buffer(YY_CURRENT_BUFFER);

	/*
	 * Make a scan buffer with special termination needed by flex.
	 */
	scanbuf = (char *) palloc(slen + 2);
	memcpy(scanbuf, str, slen);
	scanbuf[slen] = scanbuf[slen + 1] = YY_END_OF_BUFFER_CHAR;
	scanbufhandle = yy_scan_buffer(scanbuf, slen + 2);
}

void
replication_scanner_finish()
{
	yy_delete_buffer(scanbufhandle);
	scanbufhandle = NULL;
}
