class EADSerializer < ASpaceExport::Serializer
  serializer_for :ead

  def stream(data)
    @stream_handler = ASpaceExport::StreamHandler.new
    @fragments = ASpaceExport::RawXMLHandler.new
    @include_unpublished = data.include_unpublished?
    @include_daos = data.include_daos?
    @use_numbered_c_tags = data.use_numbered_c_tags?
    @id_prefix = I18n.t('archival_object.ref_id_export_prefix', :default => 'aspace_')

    doc = Nokogiri::XML::Builder.new(:encoding => "UTF-8") do |xml|
      begin

      ead_attributes = {
        'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
        'xsi:schemaLocation' => 'urn:isbn:1-931666-22-9 http://www.loc.gov/ead/ead.xsd',
        'xmlns:xlink' => 'http://www.w3.org/1999/xlink'
      }

      if data.publish === false
        ead_attributes['audience'] = 'internal'
      end

      xml.ead( ead_attributes ) {

        xml.text (
          @stream_handler.buffer { |xml, new_fragments|
            serialize_eadheader(data, xml, new_fragments)
          })

        atts = {:level => data.level, :otherlevel => data.other_level}
        atts.reject! {|k, v| v.nil?}

        xml.archdesc(atts) {

          xml.did {


            if (val = data.repo.name)
              xml.repository {
                xml.corpname { sanitize_mixed_content(val, xml, @fragments) }
              }
            end

            if (val = data.title)
              xml.unittitle  {   sanitize_mixed_content(val, xml, @fragments) }
            end

            serialize_origination(data, xml, @fragments)

            xml.unitid (0..3).map{|i| data.send("id_#{i}")}.compact.join('.')

            #Add second <unitid> with MS Number from user defined field
            if (!data.user_defined.nil? && !data.user_defined['string_1'].nil? && !data.user_defined['string_1'].empty?)
              xml.unitid data.user_defined['string_1']
            end

            if @include_unpublished
              data.external_ids.each do |exid|
                xml.unitid  ({ "audience" => "internal", "type" => exid['source'], "identifier" => exid['external_id']}) { xml.text exid['external_id']}
              end
            end

            if (languages = data.lang_materials)
              serialize_languages(languages, xml, @fragments)
            end

            serialize_extents(data, xml, @fragments)

            serialize_dates(data, xml, @fragments)

            serialize_did_notes(data, xml, @fragments)

            data.instances_with_sub_containers.each do |instance|
              serialize_container(instance, xml, @fragments)
            end

            EADSerializer.run_serialize_step(data, xml, @fragments, :did)

          }# </did>

          data.digital_objects.each do |dob|
            serialize_digital_object(dob, xml, @fragments)
          end

          serialize_nondid_notes(data, xml, @fragments)

          serialize_bibliographies(data, xml, @fragments)

          serialize_indexes(data, xml, @fragments)

          serialize_controlaccess(data, xml, @fragments)

          EADSerializer.run_serialize_step(data, xml, @fragments, :archdesc)

          xml.dsc {

            data.children_indexes.each do |i|
              xml.text(
                       @stream_handler.buffer {|xml, new_fragments|
                         serialize_child(data.get_child(i), xml, new_fragments)
                       }
                       )
            end
          }
        }
      }

    rescue => e
      xml.text  "ASPACE EXPORT ERROR : YOU HAVE A PROBLEM WITH YOUR EXPORT OF YOUR RESOURCE. THE FOLLOWING INFORMATION MAY HELP:\n
                MESSAGE: #{e.message.inspect}  \n
                TRACE: #{e.backtrace.inspect} \n "
    end



    end
    doc.doc.root.add_namespace nil, 'urn:isbn:1-931666-22-9'

    Enumerator.new do |y|
      @stream_handler.stream_out(doc, @fragments, y)
    end


  end

  def serialize_eadheader(data, xml, fragments)
    eadid_url = data.ead_location

    if AppConfig[:arks_enabled] && data.ark_name && (current_ark = data.ark_name.fetch('current', nil))
      eadid_url = current_ark
    end

    eadheader_atts = {:findaidstatus => data.finding_aid_status,
                      :repositoryencoding => "iso15511",
                      :countryencoding => "iso3166-1",
                      :dateencoding => "iso8601",
                      :langencoding => "iso639-2b"}.reject {|k, v| v.nil? || v.empty? || v == "null"}

    xml.eadheader(eadheader_atts) {

      if (data.user_defined['string_1'].start_with?('UA'))
        org_code = 'US-NNC-UA'
      end

      eadid_atts = {:countrycode => data.repo.country,
              :url => eadid_url,
              :mainagencycode => data.mainagencycode}.reject {|k, v| v.nil? || v.empty? || v == "null" }

      xml.eadid(eadid_atts) {
        xml.text data.ead_id
      }

      xml.filedesc {

        xml.titlestmt {

          titleproper = ""
          titleproper += "#{data.finding_aid_title} " if data.finding_aid_title
          titleproper += "#{data.title}" if ( data.title && titleproper.empty? )
          titleproper += "<num>#{(0..3).map {|i| data.send("id_#{i}")}.compact.join('.')}</num>"
          xml.titleproper("type" => "filing") { sanitize_mixed_content(data.finding_aid_filing_title, xml, fragments)} unless data.finding_aid_filing_title.nil?
          xml.titleproper { sanitize_mixed_content(titleproper, xml, fragments) }
          xml.subtitle {  sanitize_mixed_content(data.finding_aid_subtitle, xml, fragments) } unless data.finding_aid_subtitle.nil?
          xml.author { sanitize_mixed_content(data.finding_aid_author, xml, fragments) }  unless data.finding_aid_author.nil?
          xml.sponsor { sanitize_mixed_content( data.finding_aid_sponsor, xml, fragments) } unless data.finding_aid_sponsor.nil?

        }

        unless data.finding_aid_edition_statement.nil?
          xml.editionstmt {
            sanitize_mixed_content(data.finding_aid_edition_statement, xml, fragments, true )
          }
        end

        xml.publicationstmt {
          xml.publisher { sanitize_mixed_content(data.repo.name, xml, fragments) }

          if data.repo.image_url
            xml.p ( { "id" => "logostmt" } ) {
                            xml.extref ({"xlink:href" => data.repo.image_url,
                                        "xlink:actuate" => "onLoad",
                                        "xlink:show" => "embed",
                                        "xlink:type" => "simple"
                                        })
                          }
          end
          if (data.finding_aid_date)
            xml.p {
                    val = data.finding_aid_date
                    xml.date { sanitize_mixed_content( val, xml, fragments) }
                  }
          end

          unless data.addresslines.empty?
            xml.address {
              data.addresslines.each do |line|
                xml.addressline { sanitize_mixed_content( line, xml, fragments) }
              end
              if data.repo.url
                xml.addressline ( "URL: " ) {
                   xml.extptr ( {
                           "xlink:href" => data.repo.url,
                           "xlink:title" => data.repo.url,
                           "xlink:type" => "simple",
                           "xlink:show" => "new"
                           } )
                 }
              end
            }
          end

          data.metadata_rights_declarations.each do |mrd|
            if mrd["license"]
              license_translation = I18n.t("enumerations.metadata_license.#{mrd['license']}", :default => mrd['license'])
              xml.p (license_translation)
            end
          end
        }

        if (data.finding_aid_series_statement)
          val = data.finding_aid_series_statement
          xml.seriesstmt {
            sanitize_mixed_content( val, xml, fragments, true )
          }
        end
        if ( data.finding_aid_note )
          val = data.finding_aid_note
          xml.notestmt { xml.note { sanitize_mixed_content( val, xml, fragments, true )} }
        end

      }

      xml.profiledesc {
        creation = "This finding aid was produced using ArchivesSpace on <date>#{Time.now}</date>."
        xml.creation { sanitize_mixed_content( creation, xml, fragments) }

        if (val = data.finding_aid_language_note)
          xml.langusage (fragments << val)
        else
          xml.langusage() {
            xml.text(I18n.t("resource.finding_aid_langusage_label"))
            xml.language({langcode: "#{data.finding_aid_language}", :scriptcode => "#{data.finding_aid_script}"}) {
              xml.text(I18n.t("enumerations.language_iso639_2.#{data.finding_aid_language}"))
              xml.text(", ")
              xml.text(I18n.t("enumerations.script_iso15924.#{data.finding_aid_script}"))
              xml.text(" #{I18n.t("language_and_script.script").downcase}")}
            xml.text(".")
          }
        end

        if (val = data.descrules)
          xml.descrules { sanitize_mixed_content(val, xml, fragments) }
        end
      }

      export_rs = @include_unpublished ? data.revision_statements : data.revision_statements.reject { |rs| !rs['publish'] }
      if export_rs.length > 0
        xml.revisiondesc {
          export_rs.each do |rs|
            if rs['description'] && rs['description'].strip.start_with?('<')
              xml.text (fragments << rs['description'] )
            else
              xml.change(rs['publish'] ? nil : {:audience => 'internal'}) {
                rev_date = rs['date'] ? rs['date'] : ""
                xml.date (fragments <<  rev_date )
                xml.item (fragments << rs['description']) if rs['description']
              }
            end
          end
        }
      end
    }
  end

end
