class MARCModel < ASpaceExport::ExportModel
  model_for :marc21

  include JSONModel

  #don't export empty fields when using df_handler
  def self.df_handler(name, tag, ind1, ind2, code)
    define_method(name) do |val|
      if val && !val.strip.empty?
        df(tag, ind1, ind2).with_sfs([code, val])
      end
    end
    name.to_sym
  end

  @archival_object_map = {
    [:repository, :user_defined, :finding_aid_language] => :handle_repo_code,
    [:title, :linked_agents, :dates] => :handle_title,
    :linked_agents => :handle_agents,
    :subjects => :handle_subjects,
    :extents => :handle_extents,
    :lang_materials => :handle_languages
  }

  @resource_map = {
    [:id_0, :id_1, :id_2, :id_3] => :handle_id,
    :notes => :handle_notes,
    :user_defined => :handle_user_defined,
    :finding_aid_description_rules => df_handler('fadr', '040', ' ', ' ', 'e'),
    :finding_aid_note => df_handler('fan', '555', '0', ' ', 'a'),
    :ead_location => :handle_ead_loc
  }

  #Picked from new release, but added 035
  def df(*args)
    if @datafields.has_key?(args.to_s)
      # Manny Rodriguez: 3/16/18
      # Bugfix for ANW-146
      # Separate creators should go in multiple 700 fields in the output MARCXML file. This is not happening because the different 700 fields are getting mashed in under the same key in the hash below, instead of having a new hash entry created.
      # So, we'll get around that by using a different hash key if the code is 700.
      # based on MARCModel#datafields, it looks like the hash keys are thrown away outside of this class, so we can use anything as a key.
      # At the moment, we don't want to change this behavior too much in case something somewhere else is relying on the original behavior.

     if(args[0] == "700" || args[0] == "710" || args[0] == "035" || args[0] == "506")
       @datafields[rand(10000)] = @@datafield.new(*args)
     else
       @datafields[args.to_s]
     end
    else

      @datafields[args.to_s] = @@datafield.new(*args)
      @datafields[args.to_s]
    end
  end

  #Add an 035 based on string + id0
  def handle_id(*ids)
    ids.reject!{|i| i.nil? || i.empty?}
    unless ids.empty?
      df('099', ' ', ' ').with_sfs(['a', ids.join('.')])
      df('852', ' ', ' ').with_sfs(['c', ids.join('.')])
      last035 = 'CULASPC-' + ids[0]
      df('035', ' ', ' ').with_sfs(['a', last035])
    end
  end

  #Don't export language to random 04x fields
  #Should be fixed upstream soon
  def handle_language(langcode)
    df('041', '0', ' ').with_sfs(['a', langcode])
  end

  def handle_repo_code(repository, user_defined, *finding_aid_language)
    repo = repository['_resolved']
    return false unless repo

    #If string_1 starts with UA, repo code is NNC-UA
    if user_defined['string_1'].start_with?("UA")
      repo['org_code'] = "NNC-UA"
    end

    sfa = repo['org_code'] ? repo['org_code'] : "Repository: #{repo['repo_code']}"

    # ANW-529: options for 852 datafield:
    # 1.) $a => org_code || repo_name
    # 2.) $a => $parent_institution_name && $b => repo_name

    if repo['parent_institution_name']
      subfields_852 = [
                        ['a', repo['parent_institution_name']],
                        ['b', repo['name']]
                      ]
    elsif repo['org_code']
      subfields_852 = [
                        ['a', repo['org_code']],
                      ]
    else
      subfields_852 = [
                        ['a', repo['name']]
                      ]
    end

    df('852', ' ', ' ').with_sfs(*subfields_852)

    df('040', ' ', ' ').with_sfs(['a', repo['org_code']], ['b', finding_aid_language[0]], ['c', repo['org_code']])

    if repo['org_code']
      df('049', ' ', ' ').with_sfs(['a', repo['org_code']])
    end
  end

  def handle_user_defined(user_defined)
    return false if user_defined.nil?
    df('852', ' ', ' ').with_sfs(['j', user_defined['string_1']])
    df('035', ' ', ' ').with_sfs(['a', user_defined['string_2']])
    df('035', ' ', ' ').with_sfs(['a', user_defined['string_3']])
    df('035', ' ', ' ').with_sfs(['a', user_defined['string_4']])
  end

  #Remove processinfo from 500 mapping and move to 583
  def handle_notes(notes)

    notes.each do |note|

      prefix =  case note['type']
                when 'dimensions'; "Dimensions"
                when 'physdesc'; "Physical Description note"
                when 'materialspec'; "Material Specific Details"
                when 'physloc'; "Location of resource"
                when 'phystech'; "Physical Characteristics / Technical Requirements"
                when 'physfacet'; "Physical Facet"
                #when 'processinfo'; "Processing Information"
                when 'separatedmaterial'; "Materials Separated from the Resource"
                else; nil
                end

      marc_args = case note['type']

                  when 'arrangement', 'fileplan'
                    ['351', 'a']
                  # Remove processinfo from 500
                  when 'odd', 'dimensions', 'physdesc', 'materialspec', 'physloc', 'phystech', 'physfacet', 'separatedmaterial'
                    ['500','a']
                  # we would prefer that information from both the note and subnote appear in subfields of a 506 element, like this:
                    # <datafield ind1="1" ind2=" " tag="506">
                    # <subfield code="a">Restricted until 2020</subfield> <!-- from the subnote/text/content field -->
                    # <subfield code="f">Available</subfield> <!-- from the category list -->
                    # </datafield>
                  when 'accessrestrict'
                    ind1 = note['publish'] ? '1' : '0'
                    if note['publish'] || @include_unpublished
                      if note['rights_restriction']
                        result = note['rights_restriction']['local_access_restriction_type']
                        if result != []
                          result.each do |lart|
                            df('506', ind1).with_sfs(['a', note['subnotes'][0]['content']], ['f', lart])
                          end
                        else
                          df('506', ind1).with_sfs(['a', note['subnotes'][0]['content']])
                        end
                      else
                        ['506', ind1 ,'', 'a']
                      end
                    end
                  when 'scopecontent'
                    ['520', '2', ' ', 'a']
                  when 'abstract'
                    ['520', '3', ' ', 'a']
                  when 'prefercite'
                    ['524', ' ', ' ', 'a']
                  when 'acqinfo'
                    ind1 = note['publish'] ? '1' : '0'
                    ['541', ind1, ' ', 'a']
                  when 'relatedmaterial'
                    ['544','d']
                  when 'bioghist'
                    ['545','a']
                  when 'custodhist'
                    ind1 = note['publish'] ? '1' : '0'
                    ['561', ind1, ' ', 'a']
                  # Add processinfo to 583
                  when 'appraisal', 'processinfo'
                    ind1 = note['publish'] ? '1' : '0'
                    ['583', ind1, ' ', 'a']
                  when 'accruals'
                    ['584', 'a']
                  when 'altformavail'
                    ['535', '2', ' ', 'a']
                  when 'originalsloc'
                    ['535', '1', ' ', 'a']
                  when 'userestrict', 'legalstatus'
                    ['540', 'a']
                  when 'langmaterial'
                    ['546', 'a']
                  else
                    nil
                  end

      unless marc_args.nil?
        text = prefix ? "#{prefix}: " : ""
        text += ASpaceExport::Utils.extract_note_text(note, @include_unpublished)

        # only create a tag if there is text to show (e.g., marked published or exporting unpublished) and if there are not multiple local access restriction types (if there are, that's already handled above)
        unless note['type'] == 'accessrestrict' && note['rights_restriction']
          if text.length > 0
            df!(*marc_args[0...-1]).with_sfs([marc_args.last, *Array(text)])
          end
        end
      end

    end
  end

  #Remove 555 from ead_loc export, we're doing it above with fa note
  def handle_ead_loc(ead_loc)
    df('856', '4', '2').with_sfs(
                                ['z', "Finding aid online:"],
                                ['u', ead_loc]
                                ) if ead_loc
  end



end
