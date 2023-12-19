/*Iterative proportional fitting*/

%macro Nobs(dataIn);
/*Returns the number of observations in a dataset*/
	%local dataid nobs rc;
	%let nobs=0;
	%if (&dataIn ne ) %then %do;
		%let dataid=%sysfunc(open(&dataIn));
		%let nobs=%sysfunc(attrn(&dataid,nobs));
		%let rc=%sysfunc(close(&dataid));
	%end;
	&nobs 
%mend Nobs;

%macro saveOptions();
	/*save some common options*/
	%local notes mprint symbolgen source options;
	%let notes = %sysfunc(getoption(Notes));
	%let mprint = %sysfunc(getoption(mprint));
	%let symbolgen = %sysfunc(getoption(Symbolgen));
	%let source = %sysfunc(getoption(source));

	%let options = &notes &mprint &symbolgen &source;
	&options;
%mend saveOptions;

%macro Time(from);
/*returns the current time  or if input provided: 
returns the elaspsed time from the input time */
	%local dataTime now time;
	%let datetime = %sysfunc( datetime() );
	%let now=%sysfunc( timepart(&datetime) );

	%if (&from ne ) %then %do;
		%let timefrom = %sysfunc(inputn(&from,time9.));
		%if %sysevalf(&now<&timefrom) %then %do;
			%let time =  %sysevalf(86400-&timefrom,ceil);
			%let time = %sysevalf(&time + %sysevalf(&now,ceil));
		%end;
		%else %do;
			%let time = %sysevalf(&now-&timefrom,ceil);
		%end;
		%let time = %sysfunc(putn(&time,time9.));
	%end;
	%else %do;
		%let time = &now;
		%let time = %sysfunc(putn(&time,time9.));
	%end;
	&time
%mend Time;

%macro varNames(data,var,start=1);
	/*return a list of names for the variables of a Data set*/
	%local id nvar names rc N i varnum n;
	%let id= %sysfunc(open(&data));

	%if (&var eq) %then %do;
		%let nvar=%sysfunc(attrn(&id,nvar));
		%let names=;
		%do i = &start %to &nvar;
			%let names= &names %sysfunc(varName(&id,&i));
		%end;
	%end;

	%let rc= %sysfunc(close(&id));
	&names
%mend varNames;

%macro GetDiscrepancy();

	proc sql noprint;
		create table wrk_cons as
		select a._name_ as consId,  sum(a.col1 * b.weight)  as weightCoef_sum 
		from wrk_conscoef_ as a left join wrk_weights as b
		on a.unitId=b.unitid
		group by a._name_
		;
	quit;

	proc sql noprint;
		create table wrk_TargetDiff as
		select a.*,b.weightCoef_sum as targetEst
		from &targets as a left join wrk_cons as b
		on a.consId=b.consId
		;
	quit;

	data wrk_TargetDiff;
		set wrk_TargetDiff;

		diff = target-targetEst;
		adjustement = target/targetEst;

		/*clamp the adjustment factors for inequality constraints*/
		if constype = "le" and adjustement gt 1 then do;
			adjustement=1;
			diff=0;
		end;
		if constype = "ge" and adjustement lt 1 then do;
			adjustement=1;
			diff=0;
		end;

	run;

	proc sql noprint;
		select max(abs(diff)) into: maxDiscrepancy
		from wrk_TargetDiff 
		;
	quit;

%mend GetDiscrepancy;

%macro IPF(inVar,ConsCoef=,Targets=,DataOut=,tol=1,maxIter=100);
/*
inVar: File
    unitId      : numeric of string
    weight      : numeric decision variable
	lb			: numeric x >= lb
	ub			: numeric x <= up

ConsCoef : File
    unitId      : numeric or string
    (Var1..VarN):

Targets : File
    consId    	: liste des variables contenant les coefficients (Var1..VarN)
	consType	: constraint must be greater or equal (ge) the target, lesser or equal (le), or equal (eq)
    Target      : numeric

DataOut : File
    untiId      :
    weight		: numeric lb <=	w <= ub

*/
    %local i unitIdType consId TargetValues types Varnames Nunits Nvar options start Err;

    %let Start = %time();
    %let options = %saveOptions();
    option nonotes nosource;

	%put;
    %put -----------;
    %put Calibration;
    %put -----------;
    %put;

	/*Collect the values from dataset &targets*/
	proc sql noprint;
		select consId into : consId separated by " "
		from &targets;
	quit;
	proc sql noprint;
		select Target into : TargetValues separated by " "
		from &targets;
	quit;

    %let Nunits= %Nobs(&ConsCoef);
    %let VarNames = %VarNames(data=&ConsCoef,start=2);
    %let Nvar = %sysfunc(countw(&varNames));

    %put Number of equations 	: &Nvar;
    %put Number of units  	: &Nunits;
	%put ;

	/*Check the input constraints to make sure the weights are all either 1 or 0*/
	%let i =1;
	%let Err=0;
	%do %while (&i le &Nvar);
		data _null_;
			set &ConsCoef;

			if %scan(&VarNames,&i) not in (0,1) then call symputx("Err",1) ;
		run;

		%if %eval(&Err eq 1) %then %do;
			%put Error: Coefficients in file "&ConsCoef" have to be either 0 or 1;
			%goto exit;
		%end;
		%let i = %eval(&i+1);
	%end;
	

	%local maxDiscrepancy ;
	%let maxDiscrepancy=&tol;


	proc transpose data=&conscoef out= wrk_conscoef ;by unitId ;run;

	data wrk_conscoef wrk_conscoef_;
		set wrk_conscoef;

		where col1 > 0;
	run;
	
	data wrk_weights;
		set &inVar;
	run;

	%GetDiscrepancy;
	%put Initial max discrepancy : &maxDiscrepancy ;

	%let i = 0;

	%do %while ( %eval( %sysevalf(&maxDiscrepancy ge &tol) and %eval(&i le &maxIter) ) );
		/*calculate adjustements*/
		proc sql noprint;
			create table wrk_consCoefT as
			select a.*,b.adjustement
			from wrk_conscoef_ as a left join wrk_TargetDiff as b
			on a._name_=b.consId
			;
		quit;

		data wrk_conscoef;
			set wrk_consCoefT;

			col1=col1*adjustement;
			drop adjustement;
		run;

		/*compute the geometric mean of the adjustements to be made*/
		proc sql noprint;
			create table wrk_unitAdjust as
			select unitId, exp(mean(log(col1))) as adjust
			from wrk_conscoef
			group by unitId
			;
		quit;

		proc sql noprint;
			create table wrk_weights_ as
			select a.*, a.weight*b.adjust  as weight_
			from wrk_weights as a left join wrk_unitAdjust as b
			on a.unitId=b.unitId
			;
		quit;

		/*make sure the values are within bounds*/
		data wrk_weights;
			set wrk_weights_;

			weight=weight_;

			weight = max(weight,lb);
			weight = min(weight,ub);

			drop weight_;
		run;

		%GetDiscrepancy;

		%put iteration &i : &maxDiscrepancy ;
		%let i = %eval(&i+1);
	
	%end;

	data &DataOut;
		set wrk_weights;
	run;

	proc delete data = wrk_weights wrk_weights_ wrk_unitAdjust wrk_conscoef wrk_cons; run;

	%exit:
    option &options;

    %put;
    %Put Start at  	&Start;
    %put End at 	%time();
    %put Duration 	%time(&Start);
%mend IPF;
