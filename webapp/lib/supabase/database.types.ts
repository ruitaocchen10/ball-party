export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  auction: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      expire_turn: {
        Args: { p_match_id: string }
        Returns: Database["auction"]["CompositeTypes"]["turn"]
        SetofOptions: {
          from: "*"
          to: "turn"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      pass_lot: {
        Args: { p_match_id: string }
        Returns: Database["auction"]["CompositeTypes"]["turn"]
        SetofOptions: {
          from: "*"
          to: "turn"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      place_bid: {
        Args: { p_amount: number; p_match_id: string }
        Returns: Database["auction"]["CompositeTypes"]["turn"]
        SetofOptions: {
          from: "*"
          to: "turn"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      season_bounds: {
        Args: never
        Returns: Database["auction"]["CompositeTypes"]["era"]
        SetofOptions: {
          from: "*"
          to: "era"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      start: {
        Args: {
          p_match_id: string
          p_roster_preset: string
          p_scoring_mode: string
          p_season_from?: number
          p_season_to?: number
          p_token_count?: number
        }
        Returns: Database["auction"]["CompositeTypes"]["turn"]
        SetofOptions: {
          from: "*"
          to: "turn"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      state: {
        Args: { p_match_id: string }
        Returns: Database["auction"]["CompositeTypes"]["turn"]
        SetofOptions: {
          from: "*"
          to: "turn"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      submit_sealed_bid: {
        Args: { p_amount: number; p_match_id: string }
        Returns: Database["auction"]["CompositeTypes"]["turn"]
        SetofOptions: {
          from: "*"
          to: "turn"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      use_scout_token: { Args: { p_match_id: string }; Returns: string }
      use_seal_token: {
        Args: { p_match_id: string }
        Returns: Database["auction"]["CompositeTypes"]["turn"]
        SetofOptions: {
          from: "*"
          to: "turn"
          isOneToOne: true
          isSetofReturn: false
        }
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      era: {
        season_min: number | null
        season_max: number | null
        min_span: number | null
      }
      turn: {
        match_id: string | null
        lot_count: number | null
        current_lot: number | null
        turn_seat: number | null
        opener_seat: number | null
        turn_deadline: string | null
        server_now: string | null
        phase: string | null
        phase_deadline: string | null
        free_fallback_seat: number | null
        stuck_seat: number | null
      }
    }
  }
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  higher_or_lower: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      advance: {
        Args: { p_match_id: string }
        Returns: Database["higher_or_lower"]["CompositeTypes"]["board"]
        SetofOptions: {
          from: "*"
          to: "board"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      call: {
        Args: { p_direction: string; p_match_id: string }
        Returns: Database["public"]["Tables"]["higher_or_lower_calls"]["Row"]
        SetofOptions: {
          from: "*"
          to: "higher_or_lower_calls"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      season_bounds: {
        Args: never
        Returns: Database["higher_or_lower"]["CompositeTypes"]["era"]
        SetofOptions: {
          from: "*"
          to: "era"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      start: {
        Args: {
          p_match_id: string
          p_scoring_mode?: string
          p_season_from?: number
          p_season_to?: number
        }
        Returns: Database["higher_or_lower"]["CompositeTypes"]["board"]
        SetofOptions: {
          from: "*"
          to: "board"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      state: {
        Args: { p_match_id: string }
        Returns: Database["higher_or_lower"]["CompositeTypes"]["board"]
        SetofOptions: {
          from: "*"
          to: "board"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      tick: {
        Args: { p_match_id: string }
        Returns: Database["higher_or_lower"]["CompositeTypes"]["board"]
        SetofOptions: {
          from: "*"
          to: "board"
          isOneToOne: true
          isSetofReturn: false
        }
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      board: {
        match_id: string | null
        question_count: number | null
        spare_count: number | null
        current_question: number | null
        scoring_mode: string | null
        season_from: number | null
        season_to: number | null
        phase: string | null
        phase_deadline: string | null
        server_now: string | null
      }
      era: {
        season_min: number | null
        season_max: number | null
      }
    }
  }
  prompts: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      bold_prediction_counts: {
        Args: { p_post_ids: string[] }
        Returns: {
          author_count: number
          post_id: string
          prediction_count: number
        }[]
      }
      bold_predictions_for_post: {
        Args: { p_post_id: string }
        Returns: Database["public"]["Tables"]["bold_predictions"]["Row"][]
        SetofOptions: {
          from: "*"
          to: "bold_predictions"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      create_post: {
        Args: {
          p_caption: string
          p_cover_team_codes?: string[]
          p_is_opinion?: boolean
          p_lock_at: string
          p_prompt_text: string
          p_resolution_criteria: string
          p_resolution_source?: Json
          p_send_push?: boolean
          p_slots: Json
          p_template_kind: string
          p_template_name: string
        }
        Returns: string
      }
      delete_post: { Args: { p_post_id: string }; Returns: undefined }
      is_admin: { Args: never; Returns: boolean }
      my_bold_predictions: {
        Args: { p_post_id: string }
        Returns: Database["public"]["Tables"]["bold_predictions"]["Row"][]
        SetofOptions: {
          from: "*"
          to: "bold_predictions"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      player_options: {
        Args: never
        Returns: {
          display_name: string
          headshot_url: string
          player_id: string
          position: string
          team: string
        }[]
      }
      players_by_ids: {
        Args: { p_ids: string[] }
        Returns: {
          display_name: string
          headshot_url: string
          player_id: string
          position: string
          status: string
          team: string
        }[]
      }
      post_aggregates: {
        Args: { p_post_id: string }
        Returns: {
          option_id: string
          pct: number
          slot_id: string
          total_responses: number
        }[]
      }
      post_comment: {
        Args: {
          p_body: string
          p_parent_comment_id?: string
          p_post_id: string
        }
        Returns: string
      }
      power_ranking_top_five: {
        Args: { p_post_id: string }
        Returns: {
          average_rank: number
          option_id: string
          top_five_count: number
        }[]
      }
      resolve_post: {
        Args: { p_answers: Json; p_post_id: string }
        Returns: undefined
      }
      revealed_responses: {
        Args: { p_post_id: string }
        Returns: {
          chosen_option_ids: string[]
          profile_id: string
          slot_id: string
        }[]
      }
      schedule_clear: { Args: { p_slot: string }; Returns: undefined }
      schedule_get: { Args: { p_slot: string }; Returns: Json }
      schedule_link_post: {
        Args: {
          p_game_id?: string
          p_kind: string
          p_post: string
          p_season: number
          p_week: number
        }
        Returns: undefined
      }
      schedule_mark_ready: { Args: { p_slot: string }; Returns: undefined }
      schedule_prefill: { Args: never; Returns: number }
      schedule_queue: { Args: never; Returns: Json }
      schedule_range: { Args: { p_from: string; p_to: string }; Returns: Json }
      schedule_save_draft: {
        Args: {
          p_lock_at: string
          p_opens_at: string
          p_payload: Json
          p_slot: string
        }
        Returns: undefined
      }
      schedule_unready: { Args: { p_slot: string }; Returns: undefined }
      search_players: {
        Args: { p_limit?: number; p_query: string }
        Returns: {
          display_name: string
          headshot_url: string
          player_id: string
          position: string
          status: string
          team: string
        }[]
      }
      submit_bold_predictions: {
        Args: { p_post_id: string; p_predictions: Json }
        Returns: undefined
      }
      submit_response: {
        Args: { p_choices: Json; p_comment?: string; p_post_id: string }
        Returns: undefined
      }
      void_post: {
        Args: { p_post_id: string; p_reason: string }
        Returns: undefined
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      auction_bids: {
        Row: {
          action: string
          automatic: boolean
          bid_seq: number
          by_timeout: boolean
          created_at: string
          match_id: string
          price: number | null
          seq: number
          user_id: string
        }
        Insert: {
          action: string
          automatic?: boolean
          bid_seq: number
          by_timeout?: boolean
          created_at?: string
          match_id: string
          price?: number | null
          seq: number
          user_id: string
        }
        Update: {
          action?: string
          automatic?: boolean
          bid_seq?: number
          by_timeout?: boolean
          created_at?: string
          match_id?: string
          price?: number | null
          seq?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "auction_bids_match_id_seq_fkey"
            columns: ["match_id", "seq"]
            isOneToOne: false
            referencedRelation: "auction_lots"
            referencedColumns: ["match_id", "seq"]
          },
          {
            foreignKeyName: "auction_bids_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      auction_lots: {
        Row: {
          display_name: string
          headshot_url: string | null
          match_id: string
          opponent: string | null
          player_id: string
          points: number | null
          position: string
          price: number | null
          resolved_at: string | null
          season: number
          seq: number
          slot: string | null
          team: string
          week: number | null
          winner_id: string | null
        }
        Insert: {
          display_name: string
          headshot_url?: string | null
          match_id: string
          opponent?: string | null
          player_id: string
          points?: number | null
          position: string
          price?: number | null
          resolved_at?: string | null
          season: number
          seq: number
          slot?: string | null
          team: string
          week?: number | null
          winner_id?: string | null
        }
        Update: {
          display_name?: string
          headshot_url?: string | null
          match_id?: string
          opponent?: string | null
          player_id?: string
          points?: number | null
          position?: string
          price?: number | null
          resolved_at?: string | null
          season?: number
          seq?: number
          slot?: string | null
          team?: string
          week?: number | null
          winner_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "auction_lots_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "auction_lots_winner_id_fkey"
            columns: ["winner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      auction_matches: {
        Row: {
          current_lot: number
          flex_slots: number | null
          free_fallback_seat: number | null
          lot_count: number
          match_id: string
          opener_seat: number
          phase: string
          phase_deadline: string | null
          purse: number | null
          qb_slots: number | null
          rb_slots: number | null
          roster_preset: string | null
          scoring_mode: string | null
          season_from: number | null
          season_to: number | null
          stuck_seat: number | null
          te_slots: number | null
          token_count: number
          turn_deadline: string | null
          turn_seat: number | null
          wr_slots: number | null
        }
        Insert: {
          current_lot?: number
          flex_slots?: number | null
          free_fallback_seat?: number | null
          lot_count: number
          match_id: string
          opener_seat?: number
          phase?: string
          phase_deadline?: string | null
          purse?: number | null
          qb_slots?: number | null
          rb_slots?: number | null
          roster_preset?: string | null
          scoring_mode?: string | null
          season_from?: number | null
          season_to?: number | null
          stuck_seat?: number | null
          te_slots?: number | null
          token_count?: number
          turn_deadline?: string | null
          turn_seat?: number | null
          wr_slots?: number | null
        }
        Update: {
          current_lot?: number
          flex_slots?: number | null
          free_fallback_seat?: number | null
          lot_count?: number
          match_id?: string
          opener_seat?: number
          phase?: string
          phase_deadline?: string | null
          purse?: number | null
          qb_slots?: number | null
          rb_slots?: number | null
          roster_preset?: string | null
          scoring_mode?: string | null
          season_from?: number | null
          season_to?: number | null
          stuck_seat?: number | null
          te_slots?: number | null
          token_count?: number
          turn_deadline?: string | null
          turn_seat?: number | null
          wr_slots?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "auction_matches_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: true
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
        ]
      }
      auction_players: {
        Row: {
          budget: number
          match_id: string
          seat: number
          used_pass_token: boolean
          used_scout_token: boolean
          used_seal_token: boolean
          user_id: string
        }
        Insert: {
          budget?: number
          match_id: string
          seat: number
          used_pass_token?: boolean
          used_scout_token?: boolean
          used_seal_token?: boolean
          user_id: string
        }
        Update: {
          budget?: number
          match_id?: string
          seat?: number
          used_pass_token?: boolean
          used_scout_token?: boolean
          used_seal_token?: boolean
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "auction_players_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "auction_players_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      auction_scouting_hints: {
        Row: {
          created_at: string
          match_id: string
          seq: number
          tier: string
          user_id: string
        }
        Insert: {
          created_at?: string
          match_id: string
          seq: number
          tier: string
          user_id: string
        }
        Update: {
          created_at?: string
          match_id?: string
          seq?: number
          tier?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "auction_scouting_hints_match_id_seq_fkey"
            columns: ["match_id", "seq"]
            isOneToOne: false
            referencedRelation: "auction_lots"
            referencedColumns: ["match_id", "seq"]
          },
          {
            foreignKeyName: "auction_scouting_hints_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      auction_sealed_bid_statuses: {
        Row: {
          match_id: string
          seq: number
          submitted: boolean
          user_id: string
        }
        Insert: {
          match_id: string
          seq: number
          submitted?: boolean
          user_id: string
        }
        Update: {
          match_id?: string
          seq?: number
          submitted?: boolean
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "auction_sealed_bid_statuses_match_id_seq_fkey"
            columns: ["match_id", "seq"]
            isOneToOne: false
            referencedRelation: "auction_lots"
            referencedColumns: ["match_id", "seq"]
          },
          {
            foreignKeyName: "auction_sealed_bid_statuses_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      auction_sealed_bids: {
        Row: {
          amount: number
          match_id: string
          seq: number
          submitted_at: string
          user_id: string
        }
        Insert: {
          amount: number
          match_id: string
          seq: number
          submitted_at?: string
          user_id: string
        }
        Update: {
          amount?: number
          match_id?: string
          seq?: number
          submitted_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "auction_sealed_bids_match_id_seq_fkey"
            columns: ["match_id", "seq"]
            isOneToOne: false
            referencedRelation: "auction_lots"
            referencedColumns: ["match_id", "seq"]
          },
          {
            foreignKeyName: "auction_sealed_bids_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      bold_predictions: {
        Row: {
          author_id: string
          body: string
          created_at: string
          id: string
          post_id: string
          target_id: string
          target_type: string
          updated_at: string
        }
        Insert: {
          author_id: string
          body: string
          created_at?: string
          id?: string
          post_id: string
          target_id: string
          target_type: string
          updated_at?: string
        }
        Update: {
          author_id?: string
          body?: string
          created_at?: string
          id?: string
          post_id?: string
          target_id?: string
          target_type?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "bold_predictions_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bold_predictions_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "prompt_posts"
            referencedColumns: ["id"]
          },
        ]
      }
      device_tokens: {
        Row: {
          created_at: string
          environment: string
          id: string
          last_seen: string
          platform: string
          token: string
          user_id: string
        }
        Insert: {
          created_at?: string
          environment: string
          id?: string
          last_seen?: string
          platform?: string
          token: string
          user_id: string
        }
        Update: {
          created_at?: string
          environment?: string
          id?: string
          last_seen?: string
          platform?: string
          token?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "device_tokens_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      feedback: {
        Row: {
          created_at: string
          id: string
          kind: string
          message: string
          reporter_id: string | null
          route: string
          status: string
        }
        Insert: {
          created_at?: string
          id?: string
          kind: string
          message: string
          reporter_id?: string | null
          route: string
          status?: string
        }
        Update: {
          created_at?: string
          id?: string
          kind?: string
          message?: string
          reporter_id?: string | null
          route?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "feedback_reporter_id_fkey"
            columns: ["reporter_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      friendships: {
        Row: {
          addressee_id: string
          created_at: string
          id: string
          requester_id: string
          responded_at: string | null
          status: string
        }
        Insert: {
          addressee_id: string
          created_at?: string
          id?: string
          requester_id: string
          responded_at?: string | null
          status: string
        }
        Update: {
          addressee_id?: string
          created_at?: string
          id?: string
          requester_id?: string
          responded_at?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "friendships_addressee_id_fkey"
            columns: ["addressee_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "friendships_requester_id_fkey"
            columns: ["requester_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      guest_account_collisions: {
        Row: {
          account_id: string | null
          claim_nonce: string | null
          claimed_at: string | null
          created_at: string
          guest_id: string
        }
        Insert: {
          account_id?: string | null
          claim_nonce?: string | null
          claimed_at?: string | null
          created_at?: string
          guest_id: string
        }
        Update: {
          account_id?: string | null
          claim_nonce?: string | null
          claimed_at?: string | null
          created_at?: string
          guest_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "guest_account_collisions_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "guest_account_collisions_guest_id_fkey"
            columns: ["guest_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      higher_or_lower_call_statuses: {
        Row: {
          match_id: string
          question: number
          user_id: string
        }
        Insert: {
          match_id: string
          question: number
          user_id: string
        }
        Update: {
          match_id?: string
          question?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "higher_or_lower_call_statuses_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "higher_or_lower_call_statuses_match_id_user_id_fkey"
            columns: ["match_id", "user_id"]
            isOneToOne: false
            referencedRelation: "higher_or_lower_players"
            referencedColumns: ["match_id", "user_id"]
          },
          {
            foreignKeyName: "higher_or_lower_call_statuses_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      higher_or_lower_calls: {
        Row: {
          created_at: string
          direction: string | null
          match_id: string
          question: number
          timed_out: boolean
          user_id: string
        }
        Insert: {
          created_at?: string
          direction?: string | null
          match_id: string
          question: number
          timed_out?: boolean
          user_id: string
        }
        Update: {
          created_at?: string
          direction?: string | null
          match_id?: string
          question?: number
          timed_out?: boolean
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "higher_or_lower_calls_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "higher_or_lower_calls_match_id_user_id_fkey"
            columns: ["match_id", "user_id"]
            isOneToOne: false
            referencedRelation: "higher_or_lower_players"
            referencedColumns: ["match_id", "user_id"]
          },
          {
            foreignKeyName: "higher_or_lower_calls_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      higher_or_lower_cards: {
        Row: {
          display_name: string
          headshot_url: string | null
          match_id: string
          opponent: string | null
          ordinal: number
          player_id: string
          points: number | null
          position: string
          revealed_at: string | null
          season: number
          team: string
          week: number | null
        }
        Insert: {
          display_name: string
          headshot_url?: string | null
          match_id: string
          opponent?: string | null
          ordinal: number
          player_id: string
          points?: number | null
          position: string
          revealed_at?: string | null
          season: number
          team: string
          week?: number | null
        }
        Update: {
          display_name?: string
          headshot_url?: string | null
          match_id?: string
          opponent?: string | null
          ordinal?: number
          player_id?: string
          points?: number | null
          position?: string
          revealed_at?: string | null
          season?: number
          team?: string
          week?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "higher_or_lower_cards_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
        ]
      }
      higher_or_lower_matches: {
        Row: {
          current_question: number
          is_solo: boolean
          match_id: string
          phase: string
          phase_deadline: string | null
          question_count: number
          question_started_at: string | null
          scoring_mode: string
          season_from: number
          season_to: number
          spare_count: number
        }
        Insert: {
          current_question?: number
          is_solo?: boolean
          match_id: string
          phase?: string
          phase_deadline?: string | null
          question_count: number
          question_started_at?: string | null
          scoring_mode: string
          season_from: number
          season_to: number
          spare_count: number
        }
        Update: {
          current_question?: number
          is_solo?: boolean
          match_id?: string
          phase?: string
          phase_deadline?: string | null
          question_count?: number
          question_started_at?: string | null
          scoring_mode?: string
          season_from?: number
          season_to?: number
          spare_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "higher_or_lower_matches_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: true
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
        ]
      }
      higher_or_lower_player_stats: {
        Row: {
          all_time_high: number
          updated_at: string
          user_id: string
        }
        Insert: {
          all_time_high?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          all_time_high?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "higher_or_lower_player_stats_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      higher_or_lower_players: {
        Row: {
          absent: boolean
          best_streak: number
          correct_count: number
          current_streak: number
          eliminated_at: number | null
          last_seen_at: string
          match_id: string
          seat: number
          sudden_death: boolean
          user_id: string
        }
        Insert: {
          absent?: boolean
          best_streak?: number
          correct_count?: number
          current_streak?: number
          eliminated_at?: number | null
          last_seen_at?: string
          match_id: string
          seat: number
          sudden_death?: boolean
          user_id: string
        }
        Update: {
          absent?: boolean
          best_streak?: number
          correct_count?: number
          current_streak?: number
          eliminated_at?: number | null
          last_seen_at?: string
          match_id?: string
          seat?: number
          sudden_death?: boolean
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "higher_or_lower_players_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "higher_or_lower_players_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      lobbies: {
        Row: {
          closed_at: string | null
          code: string
          created_at: string
          game_format: Json
          host_id: string
          id: string
          selected_game: string | null
        }
        Insert: {
          closed_at?: string | null
          code: string
          created_at?: string
          game_format?: Json
          host_id: string
          id?: string
          selected_game?: string | null
        }
        Update: {
          closed_at?: string | null
          code?: string
          created_at?: string
          game_format?: Json
          host_id?: string
          id?: string
          selected_game?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "lobbies_host_id_fkey"
            columns: ["host_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      lobby_members: {
        Row: {
          joined_at: string
          last_seen_at: string
          left_at: string | null
          lobby_id: string
          user_id: string
        }
        Insert: {
          joined_at?: string
          last_seen_at?: string
          left_at?: string | null
          lobby_id: string
          user_id: string
        }
        Update: {
          joined_at?: string
          last_seen_at?: string
          left_at?: string | null
          lobby_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "lobby_members_lobby_id_fkey"
            columns: ["lobby_id"]
            isOneToOne: false
            referencedRelation: "lobbies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lobby_members_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      match_players: {
        Row: {
          match_id: string
          placement: number | null
          points_awarded: number | null
          raw_score: number | null
          run_id: string
          team: number | null
          user_id: string
        }
        Insert: {
          match_id: string
          placement?: number | null
          points_awarded?: number | null
          raw_score?: number | null
          run_id: string
          team?: number | null
          user_id: string
        }
        Update: {
          match_id?: string
          placement?: number | null
          points_awarded?: number | null
          raw_score?: number | null
          run_id?: string
          team?: number | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "match_players_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "match_players_run_id_user_id_fkey"
            columns: ["run_id", "user_id"]
            isOneToOne: false
            referencedRelation: "run_participants"
            referencedColumns: ["run_id", "user_id"]
          },
        ]
      }
      matches: {
        Row: {
          ended_at: string | null
          game: string
          id: string
          paused_at: string | null
          play_starts_at: string | null
          run_id: string
          seq: number
          started_at: string | null
          status: Database["public"]["Enums"]["match_status"]
        }
        Insert: {
          ended_at?: string | null
          game: string
          id?: string
          paused_at?: string | null
          play_starts_at?: string | null
          run_id: string
          seq: number
          started_at?: string | null
          status?: Database["public"]["Enums"]["match_status"]
        }
        Update: {
          ended_at?: string | null
          game?: string
          id?: string
          paused_at?: string | null
          play_starts_at?: string | null
          run_id?: string
          seq?: number
          started_at?: string | null
          status?: Database["public"]["Enums"]["match_status"]
        }
        Relationships: [
          {
            foreignKeyName: "matches_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "runs"
            referencedColumns: ["id"]
          },
        ]
      }
      nfl_games: {
        Row: {
          away_team: string
          home_team: string
          id: string
          kickoff: string
          primetime: boolean
          season: number
          stadium: string
          updated_at: string
          week: number
        }
        Insert: {
          away_team: string
          home_team: string
          id: string
          kickoff: string
          primetime?: boolean
          season: number
          stadium?: string
          updated_at?: string
          week: number
        }
        Update: {
          away_team?: string
          home_team?: string
          id?: string
          kickoff?: string
          primetime?: boolean
          season?: number
          stadium?: string
          updated_at?: string
          week?: number
        }
        Relationships: []
      }
      notifications: {
        Row: {
          actor_id: string
          created_at: string
          id: string
          read_at: string | null
          recipient_id: string
          ref_id: string
          reply_count: number
          type: string
          updated_at: string
        }
        Insert: {
          actor_id: string
          created_at?: string
          id?: string
          read_at?: string | null
          recipient_id: string
          ref_id: string
          reply_count?: number
          type: string
          updated_at?: string
        }
        Update: {
          actor_id?: string
          created_at?: string
          id?: string
          read_at?: string | null
          recipient_id?: string
          ref_id?: string
          reply_count?: number
          type?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "notifications_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_recipient_id_fkey"
            columns: ["recipient_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      post_game_actions: {
        Row: {
          choice: Database["public"]["Enums"]["post_game_choice"]
          chosen_at: string
          match_id: string
          next_match_id: string | null
        }
        Insert: {
          choice: Database["public"]["Enums"]["post_game_choice"]
          chosen_at?: string
          match_id: string
          next_match_id?: string | null
        }
        Update: {
          choice?: Database["public"]["Enums"]["post_game_choice"]
          chosen_at?: string
          match_id?: string
          next_match_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "post_game_actions_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: true
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "post_game_actions_next_match_id_fkey"
            columns: ["next_match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          avatar_url: string | null
          created_at: string
          deleted_at: string | null
          display_name: string
          id: string
          is_guest: boolean
          is_private: boolean
          updated_at: string
          username: string | null
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string
          deleted_at?: string | null
          display_name: string
          id: string
          is_guest?: boolean
          is_private?: boolean
          updated_at?: string
          username?: string | null
        }
        Update: {
          avatar_url?: string | null
          created_at?: string
          deleted_at?: string | null
          display_name?: string
          id?: string
          is_guest?: boolean
          is_private?: boolean
          updated_at?: string
          username?: string | null
        }
        Relationships: []
      }
      prompt_comments: {
        Row: {
          author_id: string
          body: string
          created_at: string
          id: string
          parent_comment_id: string | null
          post_id: string
          posted_with_pick: boolean
        }
        Insert: {
          author_id: string
          body: string
          created_at?: string
          id?: string
          parent_comment_id?: string | null
          post_id: string
          posted_with_pick?: boolean
        }
        Update: {
          author_id?: string
          body?: string
          created_at?: string
          id?: string
          parent_comment_id?: string | null
          post_id?: string
          posted_with_pick?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "prompt_comments_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "prompt_comments_parent_comment_id_fkey"
            columns: ["parent_comment_id"]
            isOneToOne: false
            referencedRelation: "prompt_comments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "prompt_comments_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "prompt_posts"
            referencedColumns: ["id"]
          },
        ]
      }
      prompt_posts: {
        Row: {
          author_id: string
          caption: string
          cover_team_codes: string[] | null
          created_at: string
          id: string
          is_opinion: boolean
          lock_at: string
          prompt_text: string
          ranking_kind: string | null
          resolution_criteria: string
          resolution_source: Json | null
          resolved_at: string | null
          status: string
          template_kind: string
          template_name: string
          void_reason: string | null
        }
        Insert: {
          author_id: string
          caption: string
          cover_team_codes?: string[] | null
          created_at?: string
          id?: string
          is_opinion?: boolean
          lock_at: string
          prompt_text: string
          ranking_kind?: string | null
          resolution_criteria: string
          resolution_source?: Json | null
          resolved_at?: string | null
          status?: string
          template_kind: string
          template_name: string
          void_reason?: string | null
        }
        Update: {
          author_id?: string
          caption?: string
          cover_team_codes?: string[] | null
          created_at?: string
          id?: string
          is_opinion?: boolean
          lock_at?: string
          prompt_text?: string
          ranking_kind?: string | null
          resolution_criteria?: string
          resolution_source?: Json | null
          resolved_at?: string | null
          status?: string
          template_kind?: string
          template_name?: string
          void_reason?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "prompt_posts_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "prompt_posts_ranking_kind_fkey"
            columns: ["ranking_kind"]
            isOneToOne: false
            referencedRelation: "ranking_list_kinds"
            referencedColumns: ["id"]
          },
        ]
      }
      prompt_responses: {
        Row: {
          chosen_option_ids: string[]
          created_at: string
          id: string
          points_earned: number | null
          post_id: string
          profile_id: string
          slot_id: string
        }
        Insert: {
          chosen_option_ids: string[]
          created_at?: string
          id?: string
          points_earned?: number | null
          post_id: string
          profile_id: string
          slot_id: string
        }
        Update: {
          chosen_option_ids?: string[]
          created_at?: string
          id?: string
          points_earned?: number | null
          post_id?: string
          profile_id?: string
          slot_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "prompt_responses_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "prompt_posts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "prompt_responses_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "prompt_responses_slot_id_fkey"
            columns: ["slot_id"]
            isOneToOne: false
            referencedRelation: "prompt_slots"
            referencedColumns: ["id"]
          },
        ]
      }
      prompt_slot_exclusions: {
        Row: {
          excluded_slot_id: string
          slot_id: string
        }
        Insert: {
          excluded_slot_id: string
          slot_id: string
        }
        Update: {
          excluded_slot_id?: string
          slot_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "prompt_slot_exclusions_excluded_slot_id_fkey"
            columns: ["excluded_slot_id"]
            isOneToOne: false
            referencedRelation: "prompt_slots"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "prompt_slot_exclusions_slot_id_fkey"
            columns: ["slot_id"]
            isOneToOne: false
            referencedRelation: "prompt_slots"
            referencedColumns: ["id"]
          },
        ]
      }
      prompt_slot_options: {
        Row: {
          cover_position: number | null
          headshot_url: string | null
          id: string
          label: string
          margin: string | null
          player_id: string | null
          slot_id: string
          sort_order: number
          sublabel: string | null
          team_code: string | null
        }
        Insert: {
          cover_position?: number | null
          headshot_url?: string | null
          id?: string
          label: string
          margin?: string | null
          player_id?: string | null
          slot_id: string
          sort_order?: number
          sublabel?: string | null
          team_code?: string | null
        }
        Update: {
          cover_position?: number | null
          headshot_url?: string | null
          id?: string
          label?: string
          margin?: string | null
          player_id?: string | null
          slot_id?: string
          sort_order?: number
          sublabel?: string | null
          team_code?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "prompt_slot_options_slot_id_fkey"
            columns: ["slot_id"]
            isOneToOne: false
            referencedRelation: "prompt_slots"
            referencedColumns: ["id"]
          },
        ]
      }
      prompt_slots: {
        Row: {
          correct_option_ids: string[] | null
          id: string
          label: string
          pick_count: number | null
          player_search: boolean
          points: number
          post_id: string
          shape: string
          sort_order: number
          source_game_id: string | null
        }
        Insert: {
          correct_option_ids?: string[] | null
          id?: string
          label: string
          pick_count?: number | null
          player_search?: boolean
          points: number
          post_id: string
          shape: string
          sort_order?: number
          source_game_id?: string | null
        }
        Update: {
          correct_option_ids?: string[] | null
          id?: string
          label?: string
          pick_count?: number | null
          player_search?: boolean
          points?: number
          post_id?: string
          shape?: string
          sort_order?: number
          source_game_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "prompt_slots_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "prompt_posts"
            referencedColumns: ["id"]
          },
        ]
      }
      push_outbox: {
        Row: {
          actor_id: string | null
          attempts: number
          available_at: string
          claimed_at: string | null
          created_at: string
          dead_at: string | null
          id: number
          item_key: string | null
          kind: string
          last_error: string | null
          post_id: string | null
          recipient_id: string
          ref_id: string
          sent_at: string | null
        }
        Insert: {
          actor_id?: string | null
          attempts?: number
          available_at?: string
          claimed_at?: string | null
          created_at?: string
          dead_at?: string | null
          id?: never
          item_key?: string | null
          kind: string
          last_error?: string | null
          post_id?: string | null
          recipient_id: string
          ref_id: string
          sent_at?: string | null
        }
        Update: {
          actor_id?: string | null
          attempts?: number
          available_at?: string
          claimed_at?: string | null
          created_at?: string
          dead_at?: string | null
          id?: never
          item_key?: string | null
          kind?: string
          last_error?: string | null
          post_id?: string | null
          recipient_id?: string
          ref_id?: string
          sent_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "push_outbox_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "push_outbox_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "prompt_posts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "push_outbox_recipient_id_fkey"
            columns: ["recipient_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      qb_season_builder_matches: {
        Row: {
          current_round: number
          drafted_at: string | null
          era: string
          match_id: string
          mode: string
          respin_used: boolean
          round_count: number
        }
        Insert: {
          current_round?: number
          drafted_at?: string | null
          era?: string
          match_id: string
          mode: string
          respin_used?: boolean
          round_count?: number
        }
        Update: {
          current_round?: number
          drafted_at?: string | null
          era?: string
          match_id?: string
          mode?: string
          respin_used?: boolean
          round_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "qb_season_builder_matches_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: true
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
        ]
      }
      qb_season_builder_picks: {
        Row: {
          display_name: string | null
          franchise_code: string
          match_id: string
          player_id: string | null
          round_number: number
          season: number
          slot: string
        }
        Insert: {
          display_name?: string | null
          franchise_code: string
          match_id: string
          player_id?: string | null
          round_number: number
          season: number
          slot: string
        }
        Update: {
          display_name?: string | null
          franchise_code?: string
          match_id?: string
          player_id?: string | null
          round_number?: number
          season?: number
          slot?: string
        }
        Relationships: [
          {
            foreignKeyName: "qb_season_builder_picks_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
        ]
      }
      qb_season_builder_player_stats: {
        Row: {
          best_score: number
          mode: string
          updated_at: string
          user_id: string
        }
        Insert: {
          best_score: number
          mode: string
          updated_at?: string
          user_id: string
        }
        Update: {
          best_score?: number
          mode?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "qb_season_builder_player_stats_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      qb_season_builder_spins: {
        Row: {
          attempt: number
          franchise_code: string
          match_id: string
          round_number: number
          season: number
        }
        Insert: {
          attempt?: number
          franchise_code: string
          match_id: string
          round_number: number
          season: number
        }
        Update: {
          attempt?: number
          franchise_code?: string
          match_id?: string
          round_number?: number
          season?: number
        }
        Relationships: [
          {
            foreignKeyName: "qb_season_builder_spins_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
        ]
      }
      ranking_list_items: {
        Row: {
          place: number
          player_id: string | null
          team_code: string | null
          version_id: string
        }
        Insert: {
          place: number
          player_id?: string | null
          team_code?: string | null
          version_id: string
        }
        Update: {
          place?: number
          player_id?: string | null
          team_code?: string | null
          version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ranking_list_items_version_id_fkey"
            columns: ["version_id"]
            isOneToOne: false
            referencedRelation: "ranking_list_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      ranking_list_kinds: {
        Row: {
          id: string
          item_kind: string
          label: string
          player_position: string | null
          sizes: number[]
        }
        Insert: {
          id: string
          item_kind: string
          label: string
          player_position?: string | null
          sizes: number[]
        }
        Update: {
          id?: string
          item_kind?: string
          label?: string
          player_position?: string | null
          sizes?: number[]
        }
        Relationships: []
      }
      ranking_list_versions: {
        Row: {
          created_at: string
          id: string
          list_id: string
          note: string | null
          post_id: string | null
          source: string
          update_post_id: string | null
          updated_at: string
          version_no: number
        }
        Insert: {
          created_at?: string
          id?: string
          list_id: string
          note?: string | null
          post_id?: string | null
          source: string
          update_post_id?: string | null
          updated_at?: string
          version_no: number
        }
        Update: {
          created_at?: string
          id?: string
          list_id?: string
          note?: string | null
          post_id?: string | null
          source?: string
          update_post_id?: string | null
          updated_at?: string
          version_no?: number
        }
        Relationships: [
          {
            foreignKeyName: "ranking_list_versions_list_id_fkey"
            columns: ["list_id"]
            isOneToOne: false
            referencedRelation: "ranking_lists"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ranking_list_versions_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "prompt_posts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ranking_list_versions_update_post_id_fkey"
            columns: ["update_post_id"]
            isOneToOne: false
            referencedRelation: "prompt_posts"
            referencedColumns: ["id"]
          },
        ]
      }
      ranking_lists: {
        Row: {
          created_at: string
          current_version_id: string | null
          id: string
          kind: string
          profile_id: string
        }
        Insert: {
          created_at?: string
          current_version_id?: string | null
          id?: string
          kind: string
          profile_id: string
        }
        Update: {
          created_at?: string
          current_version_id?: string | null
          id?: string
          kind?: string
          profile_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ranking_lists_current_version_fk"
            columns: ["current_version_id"]
            isOneToOne: false
            referencedRelation: "ranking_list_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ranking_lists_kind_fkey"
            columns: ["kind"]
            isOneToOne: false
            referencedRelation: "ranking_list_kinds"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ranking_lists_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      room_invites: {
        Row: {
          created_at: string
          id: string
          lobby_id: string
          recipient_id: string
          responded_at: string | null
          sender_id: string
          status: string
        }
        Insert: {
          created_at?: string
          id?: string
          lobby_id: string
          recipient_id: string
          responded_at?: string | null
          sender_id: string
          status?: string
        }
        Update: {
          created_at?: string
          id?: string
          lobby_id?: string
          recipient_id?: string
          responded_at?: string | null
          sender_id?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "room_invites_lobby_id_fkey"
            columns: ["lobby_id"]
            isOneToOne: false
            referencedRelation: "lobbies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "room_invites_recipient_id_fkey"
            columns: ["recipient_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "room_invites_sender_id_fkey"
            columns: ["sender_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      run_participants: {
        Row: {
          run_id: string
          score: number
          seat: number
          user_id: string
        }
        Insert: {
          run_id: string
          score?: number
          seat: number
          user_id: string
        }
        Update: {
          run_id?: string
          score?: number
          seat?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "run_participants_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "run_participants_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      runs: {
        Row: {
          ended_at: string | null
          id: string
          lobby_id: string | null
          mode: Database["public"]["Enums"]["run_mode"]
          started_at: string
          status: Database["public"]["Enums"]["run_status"]
          target_score: number | null
        }
        Insert: {
          ended_at?: string | null
          id?: string
          lobby_id?: string | null
          mode: Database["public"]["Enums"]["run_mode"]
          started_at?: string
          status?: Database["public"]["Enums"]["run_status"]
          target_score?: number | null
        }
        Update: {
          ended_at?: string | null
          id?: string
          lobby_id?: string | null
          mode?: Database["public"]["Enums"]["run_mode"]
          started_at?: string
          status?: Database["public"]["Enums"]["run_status"]
          target_score?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "runs_lobby_id_fkey"
            columns: ["lobby_id"]
            isOneToOne: false
            referencedRelation: "lobbies"
            referencedColumns: ["id"]
          },
        ]
      }
      wavelength_cards: {
        Row: {
          card_id: number
          left_label: string
          match_id: string
          right_label: string
          round: number
        }
        Insert: {
          card_id: number
          left_label: string
          match_id: string
          right_label: string
          round: number
        }
        Update: {
          card_id?: number
          left_label?: string
          match_id?: string
          right_label?: string
          round?: number
        }
        Relationships: [
          {
            foreignKeyName: "wavelength_cards_match_id_round_fkey"
            columns: ["match_id", "round"]
            isOneToOne: true
            referencedRelation: "wavelength_rounds"
            referencedColumns: ["match_id", "round"]
          },
        ]
      }
      wavelength_clue_statuses: {
        Row: {
          match_id: string
          round: number
        }
        Insert: {
          match_id: string
          round: number
        }
        Update: {
          match_id?: string
          round?: number
        }
        Relationships: [
          {
            foreignKeyName: "wavelength_clue_statuses_match_id_round_fkey"
            columns: ["match_id", "round"]
            isOneToOne: true
            referencedRelation: "wavelength_rounds"
            referencedColumns: ["match_id", "round"]
          },
        ]
      }
      wavelength_clues: {
        Row: {
          clue: string
          match_id: string
          round: number
        }
        Insert: {
          clue: string
          match_id: string
          round: number
        }
        Update: {
          clue?: string
          match_id?: string
          round?: number
        }
        Relationships: [
          {
            foreignKeyName: "wavelength_clues_match_id_round_fkey"
            columns: ["match_id", "round"]
            isOneToOne: true
            referencedRelation: "wavelength_rounds"
            referencedColumns: ["match_id", "round"]
          },
        ]
      }
      wavelength_matches: {
        Row: {
          current_round: number
          match_id: string
          mode: string
          phase: string
          phase_deadline: string | null
          phase_started_at: string
          preset: string | null
          round_count: number
        }
        Insert: {
          current_round?: number
          match_id: string
          mode: string
          phase?: string
          phase_deadline?: string | null
          phase_started_at?: string
          preset?: string | null
          round_count: number
        }
        Update: {
          current_round?: number
          match_id?: string
          mode?: string
          phase?: string
          phase_deadline?: string | null
          phase_started_at?: string
          preset?: string | null
          round_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "wavelength_matches_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: true
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
        ]
      }
      wavelength_players: {
        Row: {
          absent: boolean
          last_seen_at: string
          match_id: string
          seat: number
          team: number
          user_id: string
        }
        Insert: {
          absent?: boolean
          last_seen_at?: string
          match_id: string
          seat: number
          team: number
          user_id: string
        }
        Update: {
          absent?: boolean
          last_seen_at?: string
          match_id?: string
          seat?: number
          team?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "wavelength_players_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wavelength_players_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      wavelength_results: {
        Row: {
          bullseyes: number
          match_id: string
          mode: string
          outcome: string
          preset: string | null
          score: number
          stars: number | null
        }
        Insert: {
          bullseyes: number
          match_id: string
          mode: string
          outcome: string
          preset?: string | null
          score: number
          stars?: number | null
        }
        Update: {
          bullseyes?: number
          match_id?: string
          mode?: string
          outcome?: string
          preset?: string | null
          score?: number
          stars?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "wavelength_results_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: true
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
        ]
      }
      wavelength_rounds: {
        Row: {
          guess_position: number | null
          guesser_id: string
          match_id: string
          points: number | null
          psychic_id: string
          revealed_target: number | null
          round: number
          status: string
        }
        Insert: {
          guess_position?: number | null
          guesser_id: string
          match_id: string
          points?: number | null
          psychic_id: string
          revealed_target?: number | null
          round: number
          status?: string
        }
        Update: {
          guess_position?: number | null
          guesser_id?: string
          match_id?: string
          points?: number | null
          psychic_id?: string
          revealed_target?: number | null
          round?: number
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "wavelength_rounds_guesser_id_fkey"
            columns: ["guesser_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wavelength_rounds_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wavelength_rounds_psychic_id_fkey"
            columns: ["psychic_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      wavelength_targets: {
        Row: {
          match_id: string
          round: number
          target: number
        }
        Insert: {
          match_id: string
          round: number
          target: number
        }
        Update: {
          match_id?: string
          round?: number
          target?: number
        }
        Relationships: [
          {
            foreignKeyName: "wavelength_targets_match_id_round_fkey"
            columns: ["match_id", "round"]
            isOneToOne: true
            referencedRelation: "wavelength_rounds"
            referencedColumns: ["match_id", "round"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      accept_friend_request: { Args: { p_user_id: string }; Returns: boolean }
      accept_room_invite: {
        Args: { p_invite_id: string }
        Returns: {
          closed_at: string | null
          code: string
          created_at: string
          game_format: Json
          host_id: string
          id: string
          selected_game: string | null
        }
        SetofOptions: {
          from: "*"
          to: "lobbies"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      ball_knower_leaderboard: {
        Args: { p_limit?: number; p_scope?: string; p_window: string }
        Returns: {
          avatar_url: string
          display_name: string
          is_me: boolean
          profile_id: string
          rank: number
          ranked_count: number
          scored_picks: number
          total_points: number
          username: string
        }[]
      }
      block_user: { Args: { p_user_id: string }; Returns: boolean }
      can_see_ranking_update: { Args: { p_author: string }; Returns: boolean }
      cancel_friend_request: { Args: { p_user_id: string }; Returns: boolean }
      choose_post_game: {
        Args: {
          p_choice: Database["public"]["Enums"]["post_game_choice"]
          p_match_id: string
          p_roster_preset?: string
          p_scoring_mode?: string
          p_season_from?: number
          p_season_to?: number
        }
        Returns: {
          choice: Database["public"]["Enums"]["post_game_choice"]
          chosen_at: string
          match_id: string
          next_match_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "post_game_actions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      claim_guest_identity: { Args: never; Returns: string }
      claim_push_batch: { Args: { p_limit?: number }; Returns: Json }
      claim_schedule_digest: { Args: never; Returns: Json }
      claim_username: { Args: { p_username: string }; Returns: string }
      close_lobby: { Args: { p_lobby_id: string }; Returns: undefined }
      create_lobby: {
        Args: never
        Returns: {
          closed_at: string | null
          code: string
          created_at: string
          game_format: Json
          host_id: string
          id: string
          selected_game: string | null
        }
        SetofOptions: {
          from: "*"
          to: "lobbies"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      decline_friend_request: { Args: { p_user_id: string }; Returns: boolean }
      decline_room_invite: { Args: { p_invite_id: string }; Returns: boolean }
      delete_device_tokens: { Args: { p_tokens: string[] }; Returns: number }
      delete_own_account: { Args: never; Returns: undefined }
      finish_push: {
        Args: { p_error?: string; p_id: number; p_result: string }
        Returns: undefined
      }
      friend_activity: {
        Args: { p_before?: string; p_limit?: number }
        Returns: {
          actor_id: string
          avatar_url: string
          comment_id: string
          display_name: string
          event_type: string
          friend_count: number
          friend_rank: number
          game: string
          match_id: string
          mode: string
          occurred_at: string
          opponent_count: number
          opponent_you: boolean
          opponents: string[]
          placement: number
          points: number
          post_caption: string
          post_id: string
          raw_score: number
          reply_count: number
          response: Json
          run_mode: string
          take_body: string
          username: string
        }[]
      }
      friend_list_updates: {
        Args: { p_before?: string; p_limit?: number; p_post_id?: string }
        Returns: {
          author_id: string
          avatar_url: string
          created_at: string
          display_name: string
          item_kind: string
          items: string[]
          kind: string
          label: string
          note: string
          post_id: string
          prev_items: string[]
          username: string
          version_no: number
        }[]
      }
      friends_who_answered: {
        Args: { p_post_ids: string[] }
        Returns: {
          actor_id: string
          answered_at: string
          avatar_url: string
          display_name: string
          post_id: string
          username: string
        }[]
      }
      gamer_leaderboard: {
        Args: { p_limit?: number; p_scope?: string; p_window: string }
        Returns: {
          avatar_url: string
          display_name: string
          games_played: number
          is_me: boolean
          profile_id: string
          rank: number
          ranked_count: number
          username: string
          wins: number
        }[]
      }
      get_my_friend_code: { Args: never; Returns: string }
      get_profile: {
        Args: { p_username: string }
        Returns: {
          avatar_url: string
          can_view: boolean
          display_name: string
          is_private: boolean
          member_since: string
          profile_id: string
          relationship: string
          username: string
        }[]
      }
      get_profile_knower_highlights: {
        Args: { p_profile_id: string }
        Returns: {
          percentile: number
          total_points: number
          window_key: string
        }[]
      }
      get_profile_match_history: {
        Args: { p_profile_id: string }
        Returns: {
          ended_at: string
          game: string
          match_id: string
          mode: Database["public"]["Enums"]["run_mode"]
          placement: number
          raw_score: number
        }[]
      }
      get_ranking_list: {
        Args: { p_kind: string; p_username: string }
        Returns: {
          created_at: string
          is_current: boolean
          items: string[]
          note: string
          post_id: string
          source: string
          update_post_id: string
          updated_at: string
          version_id: string
          version_no: number
        }[]
      }
      get_ranking_lists: {
        Args: { p_username: string }
        Returns: {
          created_at: string
          item_kind: string
          items: string[]
          kind: string
          label: string
          note: string
          prev_items: string[]
          version_count: number
          version_id: string
          version_no: number
        }[]
      }
      heartbeat_lobby: { Args: { p_lobby_id: string }; Returns: undefined }
      inbox_unread_count: { Args: never; Returns: number }
      invite_friend_to_room: {
        Args: { p_friend_id: string; p_lobby_id: string }
        Returns: string
      }
      join_lobby: {
        Args: { p_code: string }
        Returns: {
          closed_at: string | null
          code: string
          created_at: string
          game_format: Json
          host_id: string
          id: string
          selected_game: string | null
        }
        SetofOptions: {
          from: "*"
          to: "lobbies"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      leave_lobby: { Args: { p_lobby_id: string }; Returns: undefined }
      list_blocked_users: {
        Args: never
        Returns: {
          avatar_url: string
          blocked_at: string
          display_name: string
          profile_id: string
          username: string
        }[]
      }
      list_friend_requests: {
        Args: never
        Returns: {
          avatar_url: string
          created_at: string
          direction: string
          display_name: string
          profile_id: string
          username: string
        }[]
      }
      list_friends: {
        Args: never
        Returns: {
          avatar_url: string
          display_name: string
          profile_id: string
          since: string
          username: string
        }[]
      }
      list_inbox: {
        Args: { p_limit?: number }
        Returns: {
          actor_avatar_url: string
          actor_display_name: string
          actor_id: string
          actor_username: string
          is_unread: boolean
          item_key: string
          kind: string
          lobby_id: string
          member_count: number
          post_id: string
          ref_id: string
          reply_count: number
          selected_game: string
          sort_at: string
          state: string
        }[]
      }
      list_room_invites: {
        Args: never
        Returns: {
          created_at: string
          invite_id: string
          lobby_id: string
          member_count: number
          selected_game: string
          sender_avatar_url: string
          sender_display_name: string
          sender_id: string
          sender_username: string
        }[]
      }
      lobby_member_match_history: {
        Args: { p_lobby_id: string }
        Returns: Database["public"]["CompositeTypes"]["match_history_row"][]
        SetofOptions: {
          from: "*"
          to: "match_history_row"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      lookup_friend_code: {
        Args: { p_code: string }
        Returns: {
          avatar_url: string
          display_name: string
          profile_id: string
          relationship: string
          username: string
        }[]
      }
      mark_all_notifications_read: { Args: never; Returns: number }
      mark_notification_read: { Args: { p_item_key: string }; Returns: boolean }
      match_play_start: { Args: { p_match_id: string }; Returns: Json }
      my_ball_knower_standing: {
        Args: { p_scope?: string; p_window: string }
        Returns: {
          min_picks: number
          rank: number
          ranked_count: number
          scored_picks: number
          status: string
          total_points: number
        }[]
      }
      my_gamer_standing: {
        Args: { p_scope?: string; p_window: string }
        Returns: {
          games_played: number
          min_wins: number
          rank: number
          ranked_count: number
          status: string
          wins: number
        }[]
      }
      my_match_history: {
        Args: never
        Returns: {
          ended_at: string
          game: string
          match_id: string
          mode: Database["public"]["Enums"]["run_mode"]
          placement: number
          raw_score: number
        }[]
      }
      my_profile_knower_highlights: {
        Args: never
        Returns: {
          percentile: number
          total_points: number
          window_key: string
        }[]
      }
      my_solo_standing: {
        Args: { p_game: string; p_mode?: string; p_scope?: string }
        Returns: {
          best_score: number
          rank: number
          ranked_count: number
          status: string
        }[]
      }
      pause_match: {
        Args: { p_match_id: string }
        Returns: {
          ended_at: string | null
          game: string
          id: string
          paused_at: string | null
          play_starts_at: string | null
          run_id: string
          seq: number
          started_at: string | null
          status: Database["public"]["Enums"]["match_status"]
        }
        SetofOptions: {
          from: "*"
          to: "matches"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      ranking_list_prefill: {
        Args: { p_post_id: string }
        Returns: {
          option_id: string
          place: number
          slot_id: string
        }[]
      }
      ranking_players: {
        Args: { p_ids: string[] }
        Returns: {
          display_name: string
          headshot_url: string
          player_id: string
          position: string
          team: string
        }[]
      }
      react_to_take: {
        Args: { p_comment_id: string; p_value: number }
        Returns: {
          my_reaction: number
          net_balls: number
        }[]
      }
      record_guest_account_collision: {
        Args: { p_nonce: string }
        Returns: undefined
      }
      redeem_friend_code: { Args: { p_code: string }; Returns: string }
      register_device_token: {
        Args: { p_environment: string; p_platform?: string; p_token: string }
        Returns: undefined
      }
      remove_friend: { Args: { p_user_id: string }; Returns: boolean }
      reset_friend_code: { Args: never; Returns: string }
      resume_match: {
        Args: { p_match_id: string }
        Returns: {
          ended_at: string | null
          game: string
          id: string
          paused_at: string | null
          play_starts_at: string | null
          run_id: string
          seq: number
          started_at: string | null
          status: Database["public"]["Enums"]["match_status"]
        }
        SetofOptions: {
          from: "*"
          to: "matches"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      save_ranking_list: {
        Args: {
          p_items: string[]
          p_kind: string
          p_note?: string
          p_publish?: boolean
        }
        Returns: string
      }
      search_users_by_username: {
        Args: { p_query: string }
        Returns: {
          avatar_url: string
          display_name: string
          profile_id: string
          relationship: string
          username: string
        }[]
      }
      select_lobby_game: {
        Args: { p_game: string; p_lobby_id: string }
        Returns: undefined
      }
      send_friend_request: { Args: { p_username: string }; Returns: string }
      set_lobby_game_format: {
        Args: { p_format: Json; p_lobby_id: string }
        Returns: undefined
      }
      set_profile_private: { Args: { p_private: boolean }; Returns: boolean }
      solo_leaderboard: {
        Args: {
          p_game: string
          p_limit?: number
          p_mode?: string
          p_scope?: string
        }
        Returns: {
          avatar_url: string
          best_score: number
          display_name: string
          is_me: boolean
          profile_id: string
          rank: number
          ranked_count: number
          username: string
        }[]
      }
      start_run: {
        Args: {
          p_game: string
          p_lobby_id: string
          p_mode: Database["public"]["Enums"]["run_mode"]
        }
        Returns: {
          ended_at: string | null
          game: string
          id: string
          paused_at: string | null
          play_starts_at: string | null
          run_id: string
          seq: number
          started_at: string | null
          status: Database["public"]["Enums"]["match_status"]
        }
        SetofOptions: {
          from: "*"
          to: "matches"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      start_solo_run: {
        Args: { p_game: string }
        Returns: {
          ended_at: string | null
          game: string
          id: string
          paused_at: string | null
          play_starts_at: string | null
          run_id: string
          seq: number
          started_at: string | null
          status: Database["public"]["Enums"]["match_status"]
        }
        SetofOptions: {
          from: "*"
          to: "matches"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      take_reaction_summary: {
        Args: { p_comment_ids: string[] }
        Returns: {
          can_dislike: boolean
          can_like: boolean
          comment_id: string
          my_reaction: number
          net_balls: number
        }[]
      }
      unblock_user: { Args: { p_user_id: string }; Returns: boolean }
      unregister_device_token: {
        Args: { p_platform?: string; p_token: string }
        Returns: boolean
      }
      username_available: { Args: { p_username: string }; Returns: boolean }
    }
    Enums: {
      match_status: "setup" | "playing" | "complete" | "abandoned" | "paused"
      post_game_choice: "replay" | "lobby"
      run_mode: "arcade" | "party" | "solo"
      run_status: "active" | "finished" | "abandoned"
    }
    CompositeTypes: {
      match_history_row: {
        user_id: string | null
        match_id: string | null
        game: string | null
        ended_at: string | null
        placement: number | null
        raw_score: number | null
      }
    }
  }
  qb_season_builder: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      finish: { Args: { p_match_id: string }; Returns: Json }
      pick: {
        Args: { p_match_id: string; p_player_id?: string; p_slot: string }
        Returns: Database["qb_season_builder"]["CompositeTypes"]["board"]
        SetofOptions: {
          from: "*"
          to: "board"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      respin: {
        Args: { p_match_id: string }
        Returns: Database["qb_season_builder"]["CompositeTypes"]["board"]
        SetofOptions: {
          from: "*"
          to: "board"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      result: { Args: { p_match_id: string }; Returns: Json }
      start: {
        Args: { p_era?: string; p_match_id: string; p_mode?: string }
        Returns: Database["qb_season_builder"]["CompositeTypes"]["board"]
        SetofOptions: {
          from: "*"
          to: "board"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      state: {
        Args: { p_match_id: string }
        Returns: Database["qb_season_builder"]["CompositeTypes"]["board"]
        SetofOptions: {
          from: "*"
          to: "board"
          isOneToOne: true
          isSetofReturn: false
        }
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      board: {
        match_id: string | null
        mode: string | null
        phase: string | null
        round_count: number | null
        current_round: number | null
        respin_used: boolean | null
        franchise_code: string | null
        season: number | null
        options: Json | null
        picks: Json | null
        shown: Json | null
        era: string | null
      }
    }
  }
  wavelength: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      lock_guess: {
        Args: { p_match_id: string; p_position: number; p_round: number }
        Returns: Database["wavelength"]["CompositeTypes"]["board"]
        SetofOptions: {
          from: "*"
          to: "board"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      next_card: {
        Args: { p_match_id: string }
        Returns: Database["wavelength"]["CompositeTypes"]["board"]
        SetofOptions: {
          from: "*"
          to: "board"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      report_needle: {
        Args: { p_match_id: string; p_position: number; p_round: number }
        Returns: undefined
      }
      start: {
        Args: { p_match_id: string; p_mode: string; p_preset?: string }
        Returns: Database["wavelength"]["CompositeTypes"]["board"]
        SetofOptions: {
          from: "*"
          to: "board"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      state: {
        Args: { p_match_id: string }
        Returns: Database["wavelength"]["CompositeTypes"]["board"]
        SetofOptions: {
          from: "*"
          to: "board"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      submit_clue: {
        Args: { p_clue: string; p_match_id: string; p_round: number }
        Returns: Database["wavelength"]["CompositeTypes"]["board"]
        SetofOptions: {
          from: "*"
          to: "board"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      tick: {
        Args: { p_match_id: string }
        Returns: Database["wavelength"]["CompositeTypes"]["board"]
        SetofOptions: {
          from: "*"
          to: "board"
          isOneToOne: true
          isSetofReturn: false
        }
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      board: {
        match_id: string | null
        mode: string | null
        preset: string | null
        round_count: number | null
        current_round: number | null
        phase: string | null
        phase_deadline: string | null
        server_now: string | null
        team_scores: number[] | null
      }
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  auction: {
    Enums: {},
  },
  graphql_public: {
    Enums: {},
  },
  higher_or_lower: {
    Enums: {},
  },
  prompts: {
    Enums: {},
  },
  public: {
    Enums: {
      match_status: ["setup", "playing", "complete", "abandoned", "paused"],
      post_game_choice: ["replay", "lobby"],
      run_mode: ["arcade", "party", "solo"],
      run_status: ["active", "finished", "abandoned"],
    },
  },
  qb_season_builder: {
    Enums: {},
  },
  wavelength: {
    Enums: {},
  },
} as const

