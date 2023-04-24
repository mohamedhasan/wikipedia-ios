import CocoaLumberjackSwift

enum MigrateMobileviewToMobileHTMLIfNecessaryError: Error {
    case noArticleURL
    case noArticleCacheController
    case noLegacyArticleData
    case noMobileHTML
}

extension MWKDataStore {
    // TODO: use this method's completion block when loading articles (in case a mobileview conversion hasn't happened yet for that article's saved data for any reason)
    func migrateMobileviewToMobileHTMLIfNecessary(article: WMFArticle, completionHandler: @escaping ((Error?) -> Void)) {
        DDLogError("migrateMobileviewToMobileHTMLIfNecessary - Begin")
        guard article.isConversionFromMobileViewNeeded == true else {
            // If conversion was previously attempted don't try again.
            completionHandler(nil)
            DDLogError("migrateMobileviewToMobileHTMLIfNecessary - End 1")
            return
        }
        
        let disableOfflineConversion = {
            DispatchQueue.main.async {
                do {
                    article.isDownloaded = false
                    article.isConversionFromMobileViewNeeded = false
                    try self.save()
                    DDLogError("migrateMobileviewToMobileHTMLIfNecessary - handleConversionFailure save")
                } catch let error {
                    DDLogError("Error updating article: \(error)")
                }
            }
        }
        
        guard let articleURL = article.url else {
            assertionFailure("Could not get article url")
            disableOfflineConversion()
            completionHandler(MigrateMobileviewToMobileHTMLIfNecessaryError.noArticleURL)
                DDLogError("migrateMobileviewToMobileHTMLIfNecessary - End 2")
            return
        }
        
        let articleCacheController = cacheController.articleCache
        let articleFolderURL = URL(fileURLWithPath: path(forArticleURL: articleURL))
        guard let legacyArticle = LegacyArticle(articleFolderURL: articleFolderURL) else {
            disableOfflineConversion()
            completionHandler(MigrateMobileviewToMobileHTMLIfNecessaryError.noLegacyArticleData)
                    DDLogError("migrateMobileviewToMobileHTMLIfNecessary - End 3")
            return
        }
        
        let removeArticleMobileviewSavedDataFolder = {
            // Remove old mobileview saved data folder for this article
            do {
                try FileManager.default.removeItem(atPath: self.path(forArticleURL: articleURL))
            } catch {
                DDLogError("Could not remove mobileview folder for articleURL: \(articleURL)")
            }
        }

        mobileviewConverter.convertMobileviewSavedDataToMobileHTML(articleURL: articleURL, article: legacyArticle) { (result, error) in
            
            guard error == nil, let result = result else {
                removeArticleMobileviewSavedDataFolder()
                disableOfflineConversion()
                completionHandler(error)
                DDLogError("migrateMobileviewToMobileHTMLIfNecessary - End 4")
                return
            }
            guard let mobileHTML = result as? String else {
                removeArticleMobileviewSavedDataFolder()
                disableOfflineConversion()
                completionHandler(MigrateMobileviewToMobileHTMLIfNecessaryError.noMobileHTML)
                DDLogError("migrateMobileviewToMobileHTMLIfNecessary - End 5")
                return
            }

            articleCacheController.cacheFromMigration(desktopArticleURL: articleURL, content: mobileHTML) { error in
                // Conversion succeeded so can safely blast old mobileview folder.
                removeArticleMobileviewSavedDataFolder()
                DispatchQueue.main.async {
                    do {
                        article.isConversionFromMobileViewNeeded = false
                        try self.save()
                        DDLogError("migrateMobileviewToMobileHTMLIfNecessary - cacheFromMigration save")
                    } catch let error {
                        completionHandler(error)
                        DDLogError("Error updating article: \(error)")
                        return
                    }
                    
                    completionHandler(nil)
                    DDLogError("migrateMobileviewToMobileHTMLIfNecessary - completion")
                }
            }
        }
    }
    
    func removeAllLegacyArticleData() {
        let fileURL = URL(fileURLWithPath: basePath)
        let titlesToRemoveFileURL = fileURL.appendingPathComponent("TitlesToRemove.plist")
        let sitesFolderURL = fileURL.appendingPathComponent("sites")
        let fm = FileManager.default
        try? fm.removeItem(at: titlesToRemoveFileURL)
        try? fm.removeItem(at: sitesFolderURL)
    }
}
