# Macro IPF  
Applies Iterative proportional fitting to a set of input weights(positive real numbers).
Finds a set of weights as close to the original values as possible such that all provided contraint are met.
The size the submitted problem is not bound by the computer's RAM.

Inequality constraints can be submited on the values of the weights as well as the values of the linear combinations.  

## Syntax:

```SAS
%macro IPF(
	inVar,
	ConsCoef=,
	Targets=,
	DataOut=,
	tol=1,
	maxIter=100
);  
```
## Parameters:
### Input:
inVar: File  
	unitId  : numeric of string  
	weight  : numeric decision variable  
	lb	: numeric x >= lb  
	ub	: numeric x <= up  

ConsCoef : File  
	unitId      : numeric or string  
	(Var1..VarN): coefficients of the linear combinations that must be statisfied. One variable per linear combination. 

Targets : File  
	consId 	: name of the variable (Var1..VarN) from file ConsCoef that contains the coefficients of this linear combination  
	consType: constraint must be greater or equal (ge) the target, lesser or equal (le), or equal (eq)  
	Target  : the value to which the linear constraint should add up to    

### Output:
DataOut : File  
	untiId  : label identifying the unit from input file inVar   
	weight	: numeric lb <=	w <= ub  


## USAGE 
```SAS
/*Example*/  
%let N=1000;  
%let inclprob =0.2;  

data prob;  
	do unitid = 1 to &N;  
		prob=&inclprob;
		output;    
	end;  
run;  

data weight;  
	set prob;  
	weight=1/prob;  
	if rand('uniform') < 0.2 then do;  
		lb=1;  
		ub=3;  
	end;  
	else do;  
		lb=1;  
		ub=10;  
	end;  
run;    

data coef;  

	do unitid = 1 to &N;
		var1=1;
		var2=rand('Bernoulli',0.5);
		var3=rand('Bernoulli',0.5);
		var4=rand('Bernoulli',0.5);
		var5=rand('Bernoulli',0.5);
		var6=rand('Bernoulli',0.5);
		var7=rand('Bernoulli',0.5);
		var8=rand('Bernoulli',0.5);
		var9=rand('Bernoulli',0.5);
		var10=rand('Bernoulli',0.5);
		output; 
	end;
run;  
data BalCoef;  
	merge weight(keep=unitid weight) coef;  
run;  
proc means data= BalCoef noprint;
	weight weight; var var1 var2 var3 var4 var5 var6 var7 var8 var9 var10;
	output out=BalSum sum= /autoname;
run;  
proc transpose data=BalSum out= TBalSum;
run;  
data targets(keep=consId consType target);  
	length consId $6;  
	set TBalSum;  
	if _N_ >2;  
	consId=_NAME_;  
	consType="eq";  
	pos=find(consID,"_");  
	consId=substr(ConsId,1,pos-1);  
	target=Col1*((rand('uniform')-0.5)/12 +1);  
run;  
data targets;  
	set targets;  
	if _N_ =1 then consType="le";  
	if _N_ =2 then consType="ge";  
run;   
*proc delete data= BalSum TBalSum;run;  

options notes;  
%IPF(weight,consCoef=coef,Targets=targets,DataOut=Calweight,tol=0.2,maxiter=400);
```
