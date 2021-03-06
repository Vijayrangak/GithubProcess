USE [OrderManagement]
GO
/****** Object:  UserDefinedFunction [dbo].[OM_AccountItemPriceGet]    Script Date: 3/20/2016 10:02:24 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER OFF
GO
--TEST
--TEST2222
ALTER FUNCTION [dbo].[OM_AccountItemPriceGet]   
(
  @ItemCode VARCHAR(16),
  @CustAcct VARCHAR(16),
  @AccountRoot VARCHAR(16),
  @NewAccountRoot VARCHAR(16),
  @Industry VARCHAR(16), 
  @IntensityLevelCode VARCHAR(8), 
  @State CHAR(2),
  @MandateCode VARCHAR(32),
  @PCLTemplateID INT
) RETURNS @Result TABLE
(
  ItemId INT, 
  Price  MONEY, 
  NoCoveragePrice MONEY, 
  MinPrice MONEY, 
  MaxPrice MONEY, 
  SalesCategoryDESC VARCHAR(64)
) 
AS
BEGIN 
    DECLARE @MandateAgreementID INT
    DECLARE @StrictPricing BIT
    DECLARE @MandatePrice MONEY 
    DECLARE @NoCoverageMandatePrice MONEY 
    
    INSERT INTO @Result 
    SELECT TOP 1
           i.ItemId,
           ips.Price,
           ips.NoCoveragePrice,
           ips.MinPrice,
           ips.MaxPrice,
           sc.SalesCategoryDesc
    FROM dbo.ItemPriceSets ips (NOLOCK) 
    INNER JOIN dbo.Items i (NOLOCK) 
       ON i.ItemId = ips.ItemId 
    INNER JOIN dbo.EntityTypeCodes e (NOLOCK) 
       ON e.EntityTypeCode = ips.EntityTypeCode 
    LEFT JOIN dbo.SalesCategories sc ON sc.SalesCategoryId = i.SalesCategoryId
    WHERE 
          i.ItemCode = @ItemCode
    AND ((ips.EntityTypeCode = 'D') 
     OR  (ips.EntityTypeCode = 'A' AND ips.EntityTypeValue = @CustAcct) 
     OR  (ips.EntityTypeCode = 'R' AND ips.EntityTypeValue = @AccountRoot) 
     OR  (ips.EntityTypeCode = 'S' AND ips.EntityTypeValue = @NewAccountRoot) 
     OR  (ips.EntityTypeCode = 'I' AND ips.EntityTypeValue = @Industry))
    AND  COALESCE(ips.EffectiveFrom, GETDATE()) <= GETDATE()   
    AND  COALESCE(ips.EffectiveTo, GETDATE()) >= GETDATE()
    AND (i.ItemCode NOT LIKE 'CUSAFR___' OR (ips.IntensityLevelCode = @IntensityLevelCode AND ips.STATE = @State))
    AND e.EntityTypeCode <> 'M'
    ORDER BY e.Precedence 
    
    -- check for mandate pricing 
    IF (@MandateCode IS NOT NULL) 
    BEGIN 
        SELECT @MandateAgreementID = [ABS DATA].dbo.MandateCodeToMandateAgreementID(@MandateCode),
               @StrictPricing = COALESCE(ma.StrictPricing,0)
        FROM [ABS DATA].dbo.MandateAgreement ma (NOLOCK) 
        WHERE EffectiveDate <= GETDATE() 
        AND (EndDate IS NULL OR EndDate >= GETDATE())
        
        IF @MandateAgreementID IS NOT NULL 
        BEGIN 

            
            SELECT @MandatePrice = Price,
                   @NoCoverageMandatePrice = NoCoveragePrice 
            FROM dbo.ItemPriceSets ips (NOLOCK) 
            WHERE ItemID = dbo.OM_ItemCodeToID(@ItemCode) 
            AND EntityTypeCode = 'M'
            AND EntityTypeValue = CAST(@MandateAgreementID AS VARCHAR) 
            AND ((PCLTemplateID = @PCLTemplateID) OR 
                 (PCLTemplateID IS NULL AND @PCLTemplateID IS NULL)) 
            IF (@MandatePrice IS NOT NULL) 
            BEGIN 
                

                UPDATE @Result 
                SET Price = CASE WHEN (@StrictPricing = 1) THEN @MandatePrice ELSE CASE WHEN Price < @MandatePrice THEN Price ELSE @MandatePrice END END,
                    NoCoveragePrice = CASE WHEN (@StrictPricing = 1) THEN @NoCoverageMandatePrice ELSE CASE WHEN NoCoveragePrice < @NoCoverageMandatePrice THEN NoCoveragePrice ELSE @NoCoverageMandatePrice END END
                
            END 
        END
    
    END
    
    RETURN 
    
END

