-- MỤC 3b(i): N01-N07 ĐIỀN THIẾU CÓ ĐIỀU KIỆN
-- Võ Minh Huy - 2311110117
-- Chỉ đọc dbo.heart_before_raw. Chỉ sửa bảng #tạm trong phiên kết nối.
-- Không UPDATE/DELETE bảng raw; không dùng file original làm bảng tra.
-- Chạy TOÀN BỘ bằng F5. Có 5 bảng kết quả cuối; các #bảng còn lại để kiểm tra.
-- Mã hồ sơ được tự tính từ dữ liệu; không cần danh sách mã ghi sẵn.
-- record_no là số thứ tự nội bộ theo mã hồ sơ, KHÔNG phải dòng CSV.
USE HeartFailure_DoAn;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
DROP PROCEDURE IF EXISTS #ComputeStatistic;
GO
CREATE PROCEDURE #ComputeStatistic
    @method varchar(10), @answer decimal(28,10) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @answer = NULL;
    IF @method = 'mode'
        SELECT TOP (1) @answer = value
        FROM #Eligible GROUP BY value
        ORDER BY COUNT(*) DESC, value ASC;
    ELSE IF @method = 'mean'
        SELECT @answer = CAST(SUM(value) AS decimal(22,6))
                         / NULLIF(CAST(COUNT(*) AS decimal(10,0)),0)
        FROM #Eligible;
    ELSE IF @method = 'median'
    BEGIN
        ;WITH Ranked AS (
            SELECT value, ROW_NUMBER() OVER(ORDER BY value,record_key) AS rn,
                   COUNT(*) OVER() AS n FROM #Eligible
        )
        SELECT @answer = CAST(SUM(value) AS decimal(22,6))
                         / NULLIF(CAST(COUNT(*) AS decimal(10,0)),0)
        FROM Ranked WHERE rn BETWEEN (n+1)/2 AND (n+2)/2;
    END;
END;
GO
DROP PROCEDURE IF EXISTS #ApplyNullRules;
GO
CREATE PROCEDURE #ApplyNullRules
AS
BEGIN
    SET NOCOUNT ON;
    DROP TABLE IF EXISTS #Targets;
    SELECT w.record_key,w.record_no,v.rule_id,v.column_name,
           r.statistic,r.decimals,o.old_value,
           CASE WHEN m.record_key IS NOT NULL THEN N'MASKED_FOR_VALIDATION'
                WHEN NULLIF(LTRIM(RTRIM(o.old_value)),N'') IS NULL THEN N'MISSING'
                WHEN TRY_CONVERT(decimal(18,6),o.old_value) IS NULL THEN N'WRONG_TYPE'
                ELSE N'INVALID_VALUE' END AS missing_reason
    INTO #Targets
    FROM #Work w
    CROSS APPLY (VALUES
(N'N01', N'sex', w.[sex]),
(N'N02', N'age', w.[age]),
(N'N03', N'creatinine_phosphokinase', w.[creatinine_phosphokinase]),
(N'N04', N'platelets', w.[platelets]),
(N'N05', N'serum_creatinine', w.[serum_creatinine]),
(N'N06', N'serum_sodium', w.[serum_sodium]),
(N'N07', N'ejection_fraction', w.[ejection_fraction])
    ) v(rule_id,column_name,value)
    JOIN #Rules r ON r.rule_id=v.rule_id
    JOIN #RawLong o ON o.record_key=w.record_key AND o.column_name=v.column_name
    LEFT JOIN #ActiveMask m ON m.record_key=w.record_key AND m.column_name=v.column_name
    WHERE v.value IS NULL;

    DECLARE @key char(64),@line int,@rule varchar(3),@column sysname,
            @method varchar(10),@decimals int,@old nvarchar(100),@reason nvarchar(40),
            @sex decimal(18,6),@anaemia decimal(18,6),@diabetes decimal(18,6),
            @smoking decimal(18,6),@high_blood_pressure decimal(18,6),@age_group int,
            @level int,@maxlevel int,@count int,@chosen int,
            @where nvarchar(2000),@expr nvarchar(2000),@description nvarchar(500),
            @sql nvarchar(max),@unrounded decimal(28,10),@value decimal(18,6),
            @set_text nvarchar(max),@donor_hash char(64);
    DECLARE target_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT record_key,record_no,rule_id,column_name,statistic,decimals,old_value,missing_reason
        FROM #Targets ORDER BY rule_id,record_no;
    OPEN target_cursor;
    FETCH NEXT FROM target_cursor INTO @key,@line,@rule,@column,@method,@decimals,@old,@reason;
    WHILE @@FETCH_STATUS=0
    BEGIN
        SELECT @sex=sex,@anaemia=anaemia,@diabetes=diabetes,@smoking=smoking,
               @high_blood_pressure=high_blood_pressure,@age_group=age_group
        FROM #Work WHERE record_key=@key;
        SELECT @maxlevel=MAX(priority) FROM #Levels WHERE rule_id=@rule;
        SELECT @level=1,@chosen=NULL,@unrounded=NULL,@value=NULL,
               @description=N'NO_ELIGIBLE_GROUP',@donor_hash=NULL,@count=0;
        WHILE @level<=@maxlevel
        BEGIN
            DELETE FROM #Eligible;
            SELECT @where=predicate,@expr=description_expression
            FROM #Levels WHERE rule_id=@rule AND priority=@level;
            SET @sql=N'INSERT INTO #Eligible(record_key,value)
                SELECT d.record_key,d.'+QUOTENAME(@column)+N' FROM #Donors d
                WHERE d.'+QUOTENAME(@column)+N' IS NOT NULL AND '+@where+N';';
            EXEC sys.sp_executesql @sql,
                N'@sex decimal(18,6),@anaemia decimal(18,6),@diabetes decimal(18,6),
                  @smoking decimal(18,6),@high_blood_pressure decimal(18,6),@age_group int',
                @sex,@anaemia,@diabetes,@smoking,@high_blood_pressure,@age_group;
            SELECT @count=COUNT(*) FROM #Eligible;
            IF @count>=5
            BEGIN
                SET @chosen=@level;
                SET @sql=N'SELECT @result='+@expr+N';';
                EXEC sys.sp_executesql @sql,
                    N'@sex decimal(18,6),@anaemia decimal(18,6),@diabetes decimal(18,6),
                      @smoking decimal(18,6),@high_blood_pressure decimal(18,6),@age_group int,
                      @result nvarchar(500) OUTPUT',
                    @sex,@anaemia,@diabetes,@smoking,@high_blood_pressure,@age_group,@description OUTPUT;
                EXEC #ComputeStatistic @method,@unrounded OUTPUT;
                SET @value=CONVERT(decimal(18,6),ROUND(@unrounded,@decimals));
                SELECT @set_text=STRING_AGG(CONVERT(nvarchar(max),record_key),N'|')
                    WITHIN GROUP(ORDER BY record_key) FROM #Eligible;
                SET @donor_hash=CONVERT(char(64),HASHBYTES('SHA2_256',@set_text),2);
                BREAK;
            END;
            SET @level+=1;
        END;
        IF @chosen IS NULL SET @count=0;
        SET @sql=N'UPDATE #Work SET '+QUOTENAME(@column)+N'=@v WHERE record_key=@k;';
        EXEC sys.sp_executesql @sql,N'@v decimal(18,6),@k char(64)',@value,@key;
        IF @column=N'age'
            UPDATE #Work SET age_group=CASE WHEN age IS NULL THEN NULL WHEN age<50 THEN 1
                WHEN age<60 THEN 2 WHEN age<70 THEN 3 ELSE 4 END WHERE record_key=@key;
        INSERT INTO #Log(record_key,record_no,column_name,old_value,missing_reason,
            rule_id,statistic,priority,group_description,donor_count,unrounded_value,
            decimals,imputed_value,donor_set_hash,status)
        VALUES(@key,@line,@column,@old,@reason,@rule,@method,@chosen,@description,@count,
            @unrounded,@decimals,@value,@donor_hash,
            CASE WHEN @value IS NULL THEN 'UNRESOLVED' ELSE 'FILLED' END);
        FETCH NEXT FROM target_cursor INTO @key,@line,@rule,@column,@method,@decimals,@old,@reason;
    END;
    CLOSE target_cursor; DEALLOCATE target_cursor;
END;
GO
IF OBJECT_ID(N'dbo.heart_before_raw',N'U') IS NULL
    THROW 51000,N'Không tìm thấy dbo.heart_before_raw.',1;

DROP TABLE IF EXISTS #Rules,#Levels,#Parsed,#Keyed,#Dedup,#Prepared,
    #RawLong,#Work,#Donors,#Eligible,#ActiveMask,#Log,#ActualWork,#ActualLog,
    #Observed,#MaskList,#ValidationCases,#Metrics;

CREATE TABLE #Rules(rule_id varchar(3) PRIMARY KEY,column_name sysname,statistic varchar(10),decimals int);
INSERT INTO #Rules VALUES
(N'N01', N'sex', N'mode', 0),
(N'N02', N'age', N'median', 1),
(N'N03', N'creatinine_phosphokinase', N'median', 0),
(N'N04', N'platelets', N'mean', 2),
(N'N05', N'serum_creatinine', N'median', 2),
(N'N06', N'serum_sodium', N'mode', 0),
(N'N07', N'ejection_fraction', N'median', 0);
CREATE TABLE #Levels(rule_id varchar(3),priority int,predicate nvarchar(2000),description_expression nvarchar(2000));
INSERT INTO #Levels VALUES
(N'N01', 1, N'd.[anaemia] = @anaemia AND d.[diabetes] = @diabetes AND d.[smoking] = @smoking AND d.[high_blood_pressure] = @high_blood_pressure', N'CONCAT(N''anaemia='', CONVERT(nvarchar(40), @anaemia), N'';diabetes='', CONVERT(nvarchar(40), @diabetes), N'';smoking='', CONVERT(nvarchar(40), @smoking), N'';high_blood_pressure='', CONVERT(nvarchar(40), @high_blood_pressure))'),
(N'N01', 2, N'd.[anaemia] = @anaemia AND d.[diabetes] = @diabetes', N'CONCAT(N''anaemia='', CONVERT(nvarchar(40), @anaemia), N'';diabetes='', CONVERT(nvarchar(40), @diabetes))'),
(N'N01', 3, N'd.[diabetes] = @diabetes', N'CONCAT(N''diabetes='', CONVERT(nvarchar(40), @diabetes))'),
(N'N01', 4, N'1=1', N'N''GLOBAL'''),
(N'N02', 1, N'd.[sex] = @sex AND d.[diabetes] = @diabetes', N'CONCAT(N''sex='', CONVERT(nvarchar(40), @sex), N'';diabetes='', CONVERT(nvarchar(40), @diabetes))'),
(N'N02', 2, N'd.[sex] = @sex', N'CONCAT(N''sex='', CONVERT(nvarchar(40), @sex))'),
(N'N02', 3, N'1=1', N'N''GLOBAL'''),
(N'N03', 1, N'd.[age_group] = @age_group AND d.[anaemia] = @anaemia', N'CONCAT(N''age_group='', CONVERT(nvarchar(40), @age_group), N'';anaemia='', CONVERT(nvarchar(40), @anaemia))'),
(N'N03', 2, N'd.[age_group] = @age_group', N'CONCAT(N''age_group='', CONVERT(nvarchar(40), @age_group))'),
(N'N03', 3, N'1=1', N'N''GLOBAL'''),
(N'N04', 1, N'd.[sex] = @sex AND d.[anaemia] = @anaemia', N'CONCAT(N''sex='', CONVERT(nvarchar(40), @sex), N'';anaemia='', CONVERT(nvarchar(40), @anaemia))'),
(N'N04', 2, N'd.[sex] = @sex', N'CONCAT(N''sex='', CONVERT(nvarchar(40), @sex))'),
(N'N04', 3, N'1=1', N'N''GLOBAL'''),
(N'N05', 1, N'd.[age_group] = @age_group AND d.[high_blood_pressure] = @high_blood_pressure', N'CONCAT(N''age_group='', CONVERT(nvarchar(40), @age_group), N'';high_blood_pressure='', CONVERT(nvarchar(40), @high_blood_pressure))'),
(N'N05', 2, N'd.[age_group] = @age_group', N'CONCAT(N''age_group='', CONVERT(nvarchar(40), @age_group))'),
(N'N05', 3, N'1=1', N'N''GLOBAL'''),
(N'N06', 1, N'd.[age_group] = @age_group AND d.[diabetes] = @diabetes', N'CONCAT(N''age_group='', CONVERT(nvarchar(40), @age_group), N'';diabetes='', CONVERT(nvarchar(40), @diabetes))'),
(N'N06', 2, N'd.[age_group] = @age_group', N'CONCAT(N''age_group='', CONVERT(nvarchar(40), @age_group))'),
(N'N06', 3, N'1=1', N'N''GLOBAL'''),
(N'N07', 1, N'd.[sex] = @sex AND d.[high_blood_pressure] = @high_blood_pressure', N'CONCAT(N''sex='', CONVERT(nvarchar(40), @sex), N'';high_blood_pressure='', CONVERT(nvarchar(40), @high_blood_pressure))'),
(N'N07', 2, N'd.[sex] = @sex', N'CONCAT(N''sex='', CONVERT(nvarchar(40), @sex))'),
(N'N07', 3, N'1=1', N'N''GLOBAL''');

-- Chuẩn hóa chỉ trên bảng tạm. Giữ giá trị cũ để lập nhật ký.
SELECT CONVERT(nvarchar(100),r.[age]) AS [raw_age],
CONVERT(nvarchar(100),r.[anaemia]) AS [raw_anaemia],
CONVERT(nvarchar(100),r.[creatinine_phosphokinase]) AS [raw_creatinine_phosphokinase],
CONVERT(nvarchar(100),r.[diabetes]) AS [raw_diabetes],
CONVERT(nvarchar(100),r.[ejection_fraction]) AS [raw_ejection_fraction],
CONVERT(nvarchar(100),r.[high_blood_pressure]) AS [raw_high_blood_pressure],
CONVERT(nvarchar(100),r.[platelets]) AS [raw_platelets],
CONVERT(nvarchar(100),r.[serum_creatinine]) AS [raw_serum_creatinine],
CONVERT(nvarchar(100),r.[serum_sodium]) AS [raw_serum_sodium],
CONVERT(nvarchar(100),r.[sex]) AS [raw_sex],
CONVERT(nvarchar(100),r.[smoking]) AS [raw_smoking],
CONVERT(nvarchar(100),r.[time]) AS [raw_time],
CONVERT(nvarchar(100),r.[DEATH_EVENT]) AS [raw_DEATH_EVENT], x.*
INTO #Parsed
FROM dbo.heart_before_raw r
CROSS APPLY (SELECT TRY_CONVERT(decimal(18,6), NULLIF(LTRIM(RTRIM(r.[age])), N'')) AS [age],
TRY_CONVERT(decimal(18,6), NULLIF(LTRIM(RTRIM(r.[anaemia])), N'')) AS [anaemia],
TRY_CONVERT(decimal(18,6), NULLIF(LTRIM(RTRIM(r.[creatinine_phosphokinase])), N'')) AS [creatinine_phosphokinase],
TRY_CONVERT(decimal(18,6), NULLIF(LTRIM(RTRIM(r.[diabetes])), N'')) AS [diabetes],
TRY_CONVERT(decimal(18,6), NULLIF(LTRIM(RTRIM(r.[ejection_fraction])), N'')) AS [ejection_fraction],
TRY_CONVERT(decimal(18,6), NULLIF(LTRIM(RTRIM(r.[high_blood_pressure])), N'')) AS [high_blood_pressure],
TRY_CONVERT(decimal(18,6), NULLIF(LTRIM(RTRIM(r.[platelets])), N'')) AS [platelets],
TRY_CONVERT(decimal(18,6), NULLIF(LTRIM(RTRIM(r.[serum_creatinine])), N'')) AS [serum_creatinine],
TRY_CONVERT(decimal(18,6), NULLIF(LTRIM(RTRIM(r.[serum_sodium])), N'')) AS [serum_sodium],
TRY_CONVERT(decimal(18,6), CASE LOWER(LTRIM(RTRIM(r.sex))) WHEN N'm' THEN N'1' WHEN N'male' THEN N'1' WHEN N'f' THEN N'0' WHEN N'female' THEN N'0' ELSE NULLIF(LTRIM(RTRIM(r.sex)),N'') END) AS [sex],
TRY_CONVERT(decimal(18,6), NULLIF(LTRIM(RTRIM(r.[smoking])), N'')) AS [smoking],
TRY_CONVERT(decimal(18,6), NULLIF(LTRIM(RTRIM(r.[time])), N'')) AS [time],
TRY_CONVERT(decimal(18,6), NULLIF(LTRIM(RTRIM(r.[DEATH_EVENT])), N'')) AS [DEATH_EVENT]) x
WHERE NOT (NULLIF(LTRIM(RTRIM(r.[age])), N'') IS NULL AND NULLIF(LTRIM(RTRIM(r.[anaemia])), N'') IS NULL AND NULLIF(LTRIM(RTRIM(r.[creatinine_phosphokinase])), N'') IS NULL AND NULLIF(LTRIM(RTRIM(r.[diabetes])), N'') IS NULL AND NULLIF(LTRIM(RTRIM(r.[ejection_fraction])), N'') IS NULL AND NULLIF(LTRIM(RTRIM(r.[high_blood_pressure])), N'') IS NULL AND NULLIF(LTRIM(RTRIM(r.[platelets])), N'') IS NULL AND NULLIF(LTRIM(RTRIM(r.[serum_creatinine])), N'') IS NULL AND NULLIF(LTRIM(RTRIM(r.[serum_sodium])), N'') IS NULL AND NULLIF(LTRIM(RTRIM(r.[sex])), N'') IS NULL AND NULLIF(LTRIM(RTRIM(r.[smoking])), N'') IS NULL AND NULLIF(LTRIM(RTRIM(r.[time])), N'') IS NULL AND NULLIF(LTRIM(RTRIM(r.[DEATH_EVENT])), N'') IS NULL);

SELECT t.*,CONVERT(char(64),HASHBYTES('SHA2_256',CONCAT(CONVERT(nvarchar(max), N'age='), COALESCE(CONVERT(nvarchar(40), x.[age]), N'~'), N'|anaemia=', COALESCE(CONVERT(nvarchar(40), x.[anaemia]), N'~'), N'|creatinine_phosphokinase=', COALESCE(CONVERT(nvarchar(40), x.[creatinine_phosphokinase]), N'~'), N'|diabetes=', COALESCE(CONVERT(nvarchar(40), x.[diabetes]), N'~'), N'|ejection_fraction=', COALESCE(CONVERT(nvarchar(40), x.[ejection_fraction]), N'~'), N'|high_blood_pressure=', COALESCE(CONVERT(nvarchar(40), x.[high_blood_pressure]), N'~'), N'|platelets=', COALESCE(CONVERT(nvarchar(40), x.[platelets]), N'~'), N'|serum_creatinine=', COALESCE(CONVERT(nvarchar(40), x.[serum_creatinine]), N'~'), N'|serum_sodium=', COALESCE(CONVERT(nvarchar(40), x.[serum_sodium]), N'~'), N'|sex=', COALESCE(CONVERT(nvarchar(40), x.[sex]), N'~'), N'|smoking=', COALESCE(CONVERT(nvarchar(40), x.[smoking]), N'~'), N'|time=', COALESCE(CONVERT(nvarchar(40), x.[time]), N'~'), N'|DEATH_EVENT=', COALESCE(CONVERT(nvarchar(40), x.[DEATH_EVENT]), N'~'))),2) AS record_key
INTO #Keyed
FROM #Parsed t
CROSS APPLY (SELECT t.[age], t.[anaemia], t.[creatinine_phosphokinase], t.[diabetes], t.[ejection_fraction], t.[high_blood_pressure], t.[platelets], t.[serum_creatinine], t.[serum_sodium], t.[sex], t.[smoking], t.[time], t.[DEATH_EVENT]) x;
SELECT k.*,CONVERT(int,DENSE_RANK() OVER(ORDER BY k.record_key)) AS record_no,
       ROW_NUMBER() OVER(PARTITION BY k.record_key ORDER BY k.record_key) AS duplicate_rank
INTO #Dedup FROM #Keyed k;
SELECT record_key,record_no,[age], [anaemia], [creatinine_phosphokinase], [diabetes], [ejection_fraction], [high_blood_pressure], [platelets], [serum_creatinine], [serum_sodium], [sex], [smoking], [time], [DEATH_EVENT],CAST(NULL AS int) AS age_group,
       CONVERT(bit,CASE WHEN DEATH_EVENT IN(0,1) THEN 0 ELSE 1 END) AS invalid_target
INTO #Prepared FROM #Dedup WHERE duplicate_rank=1;

UPDATE #Prepared SET age=NULL WHERE age IN(-12,250);
UPDATE #Prepared SET creatinine_phosphokinase=NULL WHERE creatinine_phosphokinase=99999;
UPDATE #Prepared SET serum_sodium=NULL WHERE serum_sodium=999;
UPDATE #Prepared SET ejection_fraction=NULL WHERE ejection_fraction=150;
UPDATE #Prepared SET age_group=CASE WHEN age IS NULL THEN NULL WHEN age<50 THEN 1
    WHEN age<60 THEN 2 WHEN age<70 THEN 3 ELSE 4 END;

SELECT d.record_key,v.column_name,v.old_value INTO #RawLong
FROM #Dedup d CROSS APPLY(VALUES (N'sex', d.[raw_sex]),
(N'age', d.[raw_age]),
(N'creatinine_phosphokinase', d.[raw_creatinine_phosphokinase]),
(N'platelets', d.[raw_platelets]),
(N'serum_creatinine', d.[raw_serum_creatinine]),
(N'serum_sodium', d.[raw_serum_sodium]),
(N'ejection_fraction', d.[raw_ejection_fraction])) v(column_name,old_value)
WHERE d.duplicate_rank=1;
SELECT * INTO #Work FROM #Prepared;
SELECT * INTO #Donors FROM #Prepared;
CREATE TABLE #Eligible(record_key char(64) PRIMARY KEY,value decimal(18,6) NOT NULL);
CREATE TABLE #ActiveMask(record_key char(64),column_name sysname,PRIMARY KEY(record_key,column_name));
CREATE TABLE #Log(record_key char(64),record_no int,column_name sysname,
    old_value nvarchar(100),missing_reason nvarchar(40),rule_id varchar(3),statistic varchar(10),
    priority int,group_description nvarchar(500),donor_count int,unrounded_value decimal(28,10),
    decimals int,imputed_value decimal(18,6),donor_set_hash char(64),status varchar(20));

EXEC #ApplyNullRules;
SELECT * INTO #ActualWork FROM #Work;
SELECT * INTO #ActualLog FROM #Log;
IF (SELECT COUNT(*) FROM #ActualWork)<>299 OR (SELECT COUNT(*) FROM #ActualLog)<>126
    THROW 51002,N'Quy mô kết quả khác 299 hồ sơ và 126 ô; cần kiểm tra trước khi sử dụng.',1;
IF EXISTS(SELECT 1 FROM #ActualLog WHERE status<>'FILLED')
    THROW 51003,N'Có ô chưa điền được. Không coi NULL là 0.',1;

-- KIỂM CHỨNG: che ceil(20% * n) từng cột theo thứ tự hash có seed 42.
-- Không dùng đáp án bị che trong mẫu cho; nếu che age thì xóa cả age_group.
SELECT w.record_key,w.record_no,v.rule_id,v.column_name,v.value AS truth,
       ROW_NUMBER() OVER(PARTITION BY v.rule_id ORDER BY
         HASHBYTES('SHA2_256',CONCAT(N'42|',v.rule_id,N'|',w.record_key)),w.record_key) AS mask_rank,
       COUNT(*) OVER(PARTITION BY v.rule_id) AS observed_count
INTO #Observed FROM #Prepared w CROSS APPLY(VALUES (N'N01', N'sex', w.[sex]),
(N'N02', N'age', w.[age]),
(N'N03', N'creatinine_phosphokinase', w.[creatinine_phosphokinase]),
(N'N04', N'platelets', w.[platelets]),
(N'N05', N'serum_creatinine', w.[serum_creatinine]),
(N'N06', N'serum_sodium', w.[serum_sodium]),
(N'N07', N'ejection_fraction', w.[ejection_fraction])) v(rule_id,column_name,value)
WHERE v.value IS NOT NULL;
SELECT * INTO #MaskList FROM #Observed WHERE mask_rank<=(observed_count+4)/5;
CREATE TABLE #ValidationCases(rule_id varchar(3),column_name sysname,record_key char(64),
    record_no int,truth decimal(18,6),prediction decimal(18,6),baseline decimal(18,6));
CREATE TABLE #Metrics(rule_id varchar(3),column_name sysname,hidden_count int,predicted_count int,
    metric varchar(10),group_score decimal(28,10),baseline_score decimal(28,10),
    baseline_value decimal(18,6),better_than_baseline bit);
DECLARE @vrule varchar(3),@vcolumn sysname,@vmethod varchar(10),@vdecimals int,
        @vsql nvarchar(max),@base_stat decimal(28,10),@baseline decimal(18,6);
DECLARE validation_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT rule_id,column_name,statistic,decimals FROM #Rules ORDER BY rule_id;
OPEN validation_cursor;
FETCH NEXT FROM validation_cursor INTO @vrule,@vcolumn,@vmethod,@vdecimals;
WHILE @@FETCH_STATUS=0
BEGIN
    TRUNCATE TABLE #Work; INSERT INTO #Work SELECT * FROM #Prepared;
    TRUNCATE TABLE #Donors;
    TRUNCATE TABLE #Log;
    TRUNCATE TABLE #ActiveMask;
    INSERT INTO #ActiveMask SELECT record_key,column_name FROM #MaskList WHERE rule_id=@vrule;
    SET @vsql=N'UPDATE w SET '+QUOTENAME(@vcolumn)+N'=NULL FROM #Work w
        JOIN #ActiveMask m ON m.record_key=w.record_key;';
    EXEC sys.sp_executesql @vsql;
    IF @vcolumn=N'age'
        UPDATE w SET age_group=NULL FROM #Work w JOIN #ActiveMask m ON m.record_key=w.record_key;
    INSERT INTO #Donors SELECT * FROM #Work;
    EXEC #ApplyNullRules;
    DELETE FROM #Eligible;
    SET @vsql=N'INSERT INTO #Eligible SELECT record_key,'+QUOTENAME(@vcolumn)+
        N' FROM #Donors WHERE '+QUOTENAME(@vcolumn)+N' IS NOT NULL;';
    EXEC sys.sp_executesql @vsql;
    EXEC #ComputeStatistic @vmethod,@base_stat OUTPUT;
    SET @baseline=CONVERT(decimal(18,6),ROUND(@base_stat,@vdecimals));
    INSERT INTO #ValidationCases
    SELECT @vrule,@vcolumn,w.record_key,w.record_no,m.truth,v.value,@baseline
    FROM #Work w JOIN #MaskList m ON m.record_key=w.record_key AND m.rule_id=@vrule
    CROSS APPLY(VALUES (N'N01', N'sex', w.[sex]),
(N'N02', N'age', w.[age]),
(N'N03', N'creatinine_phosphokinase', w.[creatinine_phosphokinase]),
(N'N04', N'platelets', w.[platelets]),
(N'N05', N'serum_creatinine', w.[serum_creatinine]),
(N'N06', N'serum_sodium', w.[serum_sodium]),
(N'N07', N'ejection_fraction', w.[ejection_fraction])) v(rule_id,column_name,value)
    WHERE v.rule_id=@vrule;
    INSERT INTO #Metrics(rule_id,column_name,hidden_count,predicted_count,metric,
        group_score,baseline_score,baseline_value)
    SELECT @vrule,@vcolumn,COUNT(*),COUNT(prediction),
        CASE WHEN @vcolumn=N'sex' THEN 'accuracy' ELSE 'MAE' END,
        CASE WHEN COUNT(prediction)<>COUNT(*) THEN NULL
             WHEN @vcolumn=N'sex' THEN
                CAST(SUM(CASE WHEN prediction=truth THEN 1 ELSE 0 END) AS decimal(22,6))/CAST(COUNT(*) AS decimal(10,0))
             ELSE CAST(SUM(ABS(prediction-truth)) AS decimal(22,6))/CAST(COUNT(*) AS decimal(10,0)) END,
        CASE WHEN @vcolumn=N'sex' THEN
                CAST(SUM(CASE WHEN baseline=truth THEN 1 ELSE 0 END) AS decimal(22,6))/CAST(COUNT(*) AS decimal(10,0))
             ELSE CAST(SUM(ABS(baseline-truth)) AS decimal(22,6))/CAST(COUNT(*) AS decimal(10,0)) END,
        @baseline
    FROM #ValidationCases WHERE rule_id=@vrule;
    FETCH NEXT FROM validation_cursor INTO @vrule,@vcolumn,@vmethod,@vdecimals;
END;
CLOSE validation_cursor; DEALLOCATE validation_cursor;
UPDATE #Metrics SET better_than_baseline=CASE WHEN group_score IS NULL THEN 0
    WHEN metric='accuracy' AND group_score>baseline_score THEN 1
    WHEN metric='MAE' AND group_score<baseline_score THEN 1 ELSE 0 END;

-- Khôi phục các #bảng làm việc về kết quả điền thật sau khi kiểm chứng.
TRUNCATE TABLE #Work; INSERT INTO #Work SELECT * FROM #ActualWork;
TRUNCATE TABLE #Donors; INSERT INTO #Donors SELECT * FROM #Prepared;
TRUNCATE TABLE #Log; INSERT INTO #Log SELECT * FROM #ActualLog;
TRUNCATE TABLE #ActiveMask;

-- KẾT QUẢ 1: chuẩn bị và số ô đã điền.
SELECT (SELECT COUNT(*) FROM dbo.heart_before_raw) AS source_rows,
    (SELECT COUNT(*) FROM dbo.heart_before_raw)-(SELECT COUNT(*) FROM #Parsed) AS empty_rows_removed,
    (SELECT COUNT(*) FROM #Parsed)-(SELECT COUNT(*) FROM #Prepared) AS duplicate_rows_removed,
    (SELECT COUNT(*) FROM #ActualWork) AS working_rows,
    COUNT(*) AS cells_to_impute,
    SUM(CASE WHEN status='FILLED' THEN 1 ELSE 0 END) AS filled_cells,
    SUM(CASE WHEN status<>'FILLED' THEN 1 ELSE 0 END) AS unresolved_cells,
    (SELECT COUNT(*) FROM #ActualWork WHERE invalid_target=1) AS invalid_target_rows
FROM #ActualLog;

-- KẾT QUẢ 2: tổng hợp N01-N07.
SELECT rule_id,column_name,COUNT(*) AS missing_cells,
    SUM(CASE WHEN status='FILLED' THEN 1 ELSE 0 END) AS filled_cells,
    SUM(CASE WHEN priority>1 THEN 1 ELSE 0 END) AS fallback_cells,
    MIN(donor_count) AS min_donors,MAX(donor_count) AS max_donors
FROM #ActualLog GROUP BY rule_id,column_name ORDER BY rule_id;

-- KẾT QUẢ 3: hai ví dụ mỗi quy tắc. Nhật ký đủ ở #ActualLog.
;WITH Examples AS (
    SELECT *,ROW_NUMBER() OVER(PARTITION BY rule_id ORDER BY record_no) AS rn
    FROM #ActualLog
)
SELECT rule_id,record_no,column_name,old_value,missing_reason,
       priority,donor_count,imputed_value
FROM Examples WHERE rn<=2 ORDER BY rule_id,record_no;

-- KẾT QUẢ 4: kiểm chứng. Accuracy cao hơn tốt hơn; MAE thấp hơn tốt hơn.
SELECT * FROM #Metrics ORDER BY rule_id;

-- KẾT QUẢ 5: nhãn sai được giữ và gắn cờ, không tự điền nhãn.
SELECT record_no,DEATH_EVENT,invalid_target FROM #ActualWork WHERE invalid_target=1;

-- Khi cần kiểm tra thêm, chạy trong CÙNG tab/phiên kết nối:
-- SELECT * FROM #ActualLog ORDER BY rule_id,record_no;
-- SELECT * FROM #ActualWork ORDER BY record_no;
-- SELECT * FROM #ValidationCases ORDER BY rule_id,record_no;
