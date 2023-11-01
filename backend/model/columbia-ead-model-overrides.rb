class EADModel < ASpaceExport::ExportModel
  model_for :ead

  include ASpaceExport::ArchivalObjectDescriptionHelpers
  include ASpaceExport::LazyChildEnumerations

  def mainagencycode
    if (user_defined && user_defined['string_1'] && user_defined['string_1'].start_with?("UA"))
      repo['org_code'] = "NNC-UA"
    end
    @mainagencycode ||= repo.country && repo.org_code ? [repo.country, repo.org_code].join('-') : nil
    @mainagencycode
  end
end
