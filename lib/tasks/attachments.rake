namespace :attachments do
  desc "Backfill the :cover/:tile variants for attachments uploaded before preprocessing existed. Run manually — not wired into deploy."
  task preprocess_covers: :environment do
    Card.find_each do |card|
      image = card.cover_image
      next unless image

      image.variant(:cover).processed
      print "."
    rescue => e
      puts "\nFailed to process cover for card #{card.id}: #{e.message}"
    end

    Board.find_each do |board|
      next unless board.avatar.attached?

      board.avatar.variant(:tile).processed
      print "."
    rescue => e
      puts "\nFailed to process tile for board #{board.id}: #{e.message}"
    end

    puts "\nDone."
  end
end
